//
//  SummarizationChatStrategy.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 26.02.2026.
//

import Foundation

/// Стратегия поведения чата с суммаризацией сообщений.
///
/// Основная логика:
/// 1. При отправке сообщения - оно появляется на экране
/// 2. LLM отвечает - ответ появляется на экране
/// 3. Если количество сообщений превысило заданное число (messagesToKeep),
///    то создаётся summary всех сообщений, кроме последних N
///
/// Как работает суммаризация:
/// - Берём все сообщения пользователя и ассистента
/// - Оставляем последние N сообщений "как есть"
/// - Остальные сообщения (кроме последних N) отправляем в LLM
///   с системным промптом (summarizationPrompt) для создания краткого резюме
/// - Полученное summary сохраняем в storage
/// - При следующих запросах summary подставляется в начало контекста
///   как system message вместе с последними N сообщениями
final class SummarizationChatStrategy: ChatBehaviorStrategy {

    var summarizationService: SummarizationServiceProtocol?
    var summaryStorage: ConversationSummaryStorageProtocol?
    var settings: LLMSettings

    /// Количество последних сообщений, которые нужно сохранить "как есть"
    /// без суммаризации. Остальные сообщения будут сжаты в summary.
    private let messagesToKeep: Int

    init(settings: LLMSettings, messagesToKeep: Int = 10) {
        self.settings = settings
        self.messagesToKeep = messagesToKeep
    }

    /// Подготавливает сообщения для отправки в LLM API.
    ///
    /// Алгоритм:
    /// 1. Если есть сохранённое summary и количество сообщений > messagesToKeep:
    ///    - Добавляем system prompt пользователя
    ///    - Добавляем summary как первое сообщение
    ///    - Добавляем последние N сообщений
    /// 2. Иначе:
    ///    - Возвращаем все сообщения как есть
    func prepareMessages(
        session: any ChatSessionProtocol,
        systemPrompt: String
    ) async -> [[String: String]] {
        var result: [[String: String]] = []

        // Добавляем системный промпт пользователя (если есть)
        if !systemPrompt.isEmpty {
            result.append(["role": "system", "content": systemPrompt])
        }

        // Проверяем, есть ли уже созданное summary
        if let summary = await session.conversationSummary, !summary.isEmpty {
            // Фильтруем только сообщения пользователя и ассистента (исключаем system messages)
            let userAndAssistantMessages = await session.messages.filter { $0.role == .user || $0.role == .assistant }

            // Если сообщений больше, чем нужно хранить - используем summary
            if userAndAssistantMessages.count > messagesToKeep {
                // Добавляем summary как ПЕРВОЕ сообщение после system prompt
                result.append([
                    "role": "system",
                    "content": "Резюме предыдущего контекста: \(summary)"
                ])

                // Берём только последние N сообщений
                let messagesToKeepArray = Array(userAndAssistantMessages.suffix(messagesToKeep))
                for message in messagesToKeepArray {
                    // Фильтруем сообщения с ошибками и пустые
                    if message.error == nil, !message.content.isEmpty {
                        result.append([
                            "role": message.role.rawValue,
                            "content": message.content
                        ])
                    }
                }

                return result
            }
        }

        // Если summary нет или сообщений мало - возвращаем всё как есть
        let messages = await session.messagesForAPI(systemPrompt: "", summarizationStrategy: .none)
        result.append(contentsOf: messages)

        return result
    }

    /// Определяет, нужно ли создавать summary.
    ///
    /// Returns: true, если количество непустых сообщений пользователя и ассистента
    ///          превышает порог messagesToKeep
    func shouldCreateSummary(session: any ChatSessionProtocol) async -> Bool {
        let userAndAssistantMessages = await session.messages.filter { $0.role == .user || $0.role == .assistant }
        // Фильтруем только непустые сообщения
        let nonEmptyMessages = userAndAssistantMessages.filter { !$0.content.isEmpty }
        return nonEmptyMessages.count > messagesToKeep
    }

    /// Создаёт summary, если количество сообщений превысило порог.
    ///
    /// Процесс:
    /// 1. Проверяем shouldCreateSummary() - нужно ли создавать summary
    /// 2. Загружаем API ключ из keychain
    /// 3. Получаем сообщения для суммаризации (все, кроме последних N)
    /// 4. Отправляем их в LLM с системным промптом для создания summary
    /// 5. Сохраняем summary в session и storage
    /// 6. Записываем токены summary в метрики
    /// 7. Вызываем callback для уведомления UI
    func createSummaryIfNeeded(
        session: any ChatSessionProtocol,
        metricsViewModel: MetricsViewModel?,
        keychainService: KeychainServiceProtocol?,
        onSummaryCreated: ((String) -> Void)?
    ) async {
        // Шаг 1: Проверяем, нужно ли создавать summary
        guard await shouldCreateSummary(session: session) else {
            // Сообщений меньше порога - summary не нужен
            return
        }

        // Проверяем наличие необходимых зависимостей
        guard let summarizationService = summarizationService else {
            print("[SummarizationChatStrategy] Summarization service is not configured")
            return
        }

        guard let keychainService = keychainService else {
            print("[SummarizationChatStrategy] Keychain service is not configured")
            return
        }

        print("[SummarizationChatStrategy] Creating summary...")

        do {
            // Шаг 2: Загружаем API ключ
            let apiKey = try keychainService.loadAPIKey()

            // Шаг 3: Получаем предыдущее summary из сессии
            let previousSummary = await session.conversationSummary

            // Получаем сообщения для суммаризации (все, кроме последних N)
            let messagesToSummarize = await session.messagesToSummarize(keepCount: messagesToKeep)

            // Получаем последнее сообщение пользователя
            let allMessages = await session.messages
            let userMessages = allMessages.filter { $0.role == .user }
            guard let lastUserMessage = userMessages.last else {
                print("[SummarizationChatStrategy] No user message found")
                return
            }

            // Шаг 4: Отправляем в LLM для создания/обновления summary
            let (summary, promptTokens, completionTokens) = try await summarizationService.createSummary(
                messagesToSummarize: messagesToSummarize,
                previousSummary: previousSummary,
                newMessage: lastUserMessage.content,
                settings: settings,
                apiKey: apiKey
            )

            // Шаг 5: Сохраняем summary в сессию (оперативно) и в storage (постоянно)
            await session.updateSummary(summary)

            // Шаг 6: Записываем токены summary в метрики
            // Это нужно для отображения статистики использования
            await session.updateMessageSummaryTokens(
                id: messagesToSummarize.last?.id ?? UUID(),
                promptTokens: promptTokens,
                completionTokens: completionTokens
            )

            metricsViewModel?.recordSummaryTokens(promptTokens: promptTokens, completionTokens: completionTokens)

            print("[SummarizationChatStrategy] Summary created successfully")
            print("[SummarizationChatStrategy] Summary length: \(summary.count) characters")

            // Шаг 7: Уведомляем UI о создании summary
            // Это нужно для отображения системного сообщения в чате
            onSummaryCreated?(summary)

        } catch {
            print("[SummarizationChatStrategy] Failed to create summary: \(error)")
        }
    }

    /// Очищает данные сессии (summary и т.д.)
    func clearSession(session: any ChatSessionProtocol) async {
        // При очистке чата также очищаем summary
    }
}

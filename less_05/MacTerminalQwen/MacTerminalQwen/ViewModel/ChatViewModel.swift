//
//  ChatViewModel.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation
import Combine

/// ViewModel для управления состоянием чата.
@MainActor
final class ChatViewModel: ObservableObject {

    // MARK: - Published Properties

    /// Сообщения в чате
    @Published private(set) var messages: [Message] = []

    /// Текущий текст ввода
    @Published var inputText: String = ""

    /// Индикатор загрузки
    @Published private(set) var isLoading: Bool = false

    /// Текущая ошибка
    @Published private(set) var error: AppError?

    /// Метрики текущего запроса
    @Published private(set) var currentMetrics: RequestMetrics = .empty

    /// Индикатор потоковой передачи
    @Published private(set) var isStreaming: Bool = false

    /// Прогресс стриминга
    @Published private(set) var streamingProgress: StreamingProgress = .init()

    // MARK: - Dependencies

    private let streamResponseUseCase: StreamResponseUseCaseProtocol
    private let settingsService: SettingsService

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()
    private var streamCancellable: AnyCancellable?

    // MARK: - Initialization

    init(
        streamResponseUseCase: StreamResponseUseCaseProtocol,
        settingsService: SettingsService
    ) {
        self.streamResponseUseCase = streamResponseUseCase
        self.settingsService = settingsService
    }

    // MARK: - Public Methods

    /// Отправить сообщение
    func sendMessage() {
        guard !isLoading else { return }

        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            error = .emptyMessage("Сообщение")
            return
        }

        // Проверка настроек
        Task {
            let settings = await settingsService.getChatSettings()
            let apiKey = (try? await settingsService.loadAPIKey()) ?? ""

            guard !apiKey.isEmpty else {
                self.error = .validation("API Key не настроен. Проверьте настройки.")
                return
            }

            // Добавить сообщение пользователя
            let userMessage = Message.user(trimmedText)
            self.messages.append(userMessage)

            // Очистить ввод
            self.inputText = ""

            // Отправить запрос
            await self.startStreaming(settings: settings, apiKey: apiKey)
        }
    }

    /// Очистить историю чата
    func clearHistory() {
        messages.removeAll()
        currentMetrics = .empty
        error = nil
    }

    /// Отменить текущий запрос
    func cancelRequest() {
        streamCancellable?.cancel()
        isLoading = false
        isStreaming = false
    }

    /// Повторить последний запрос пользователя
    func retryLastRequest() {
        guard let lastUserMessage = messages.last(where: { $0.role == .user }) else {
            return
        }

        // Удалить возможное сообщение об ошибке
        if let lastIndex = messages.lastIndex(where: { $0.hasError }) {
            messages.remove(at: lastIndex)
        }

        inputText = lastUserMessage.content
        sendMessage()
    }

    // MARK: - Private Methods

    private func startStreaming(settings: ChatSettings, apiKey: String) async {
        isLoading = true
        isStreaming = true
        error = nil
        streamingProgress.reset()

        // Создать placeholder для ответа
        let assistantMessageId = UUID()
        messages.append(Message(id: assistantMessageId, role: .assistant, content: ""))

        let messages = self.messages.filter { $0.role != .system || $0.content.isEmpty == false }

        streamCancellable = streamResponseUseCase.execute(
            messages: messages,
            settings: settings,
            apiKey: apiKey
        )
        .sink(
            receiveCompletion: { [weak self] completion in
                Task { @MainActor in
                    self?.handleCompletion(completion)
                }
            },
            receiveValue: { [weak self] event in
                Task { @MainActor in
                    self?.handleEvent(event, assistantMessageId: assistantMessageId)
                }
            }
        )
    }

    private func handleEvent(_ event: StreamEvent, assistantMessageId: UUID) {
        switch event {
        case .started:
            streamingProgress.reset()

        case .receivedChunk(let text):
            appendToLastAssistantMessage(text, id: assistantMessageId)
            streamingProgress.appendChunk(text)

        case .metricsUpdated(let metrics):
            currentMetrics = metrics

        case .finished(let finalMessage, let metrics):
            finishStreaming(message: finalMessage, metrics: metrics)

        case .failed(let appError):
            handleError(appError, assistantMessageId: assistantMessageId)
        }
    }

    private func appendToLastAssistantMessage(_ text: String, id: UUID) {
        guard let lastIndex = messages.lastIndex(where: { $0.id == id }) else {
            return
        }

        let existingMessage = messages[lastIndex]
        let updatedMessage = Message(
            id: existingMessage.id,
            role: .assistant,
            content: existingMessage.content + text,
            timestamp: existingMessage.timestamp
        )

        messages[lastIndex] = updatedMessage
    }

    private func finishStreaming(message: Message, metrics: RequestMetrics) {
        isLoading = false
        isStreaming = false
        currentMetrics = metrics

        // Обновить сообщение с финальными данными
        if let lastIndex = messages.lastIndex(where: { $0.role == .assistant && $0.content.isEmpty }) {
            messages[lastIndex] = message
        }
    }

    private func handleError(_ appError: AppError, assistantMessageId: UUID) {
        isLoading = false
        isStreaming = false
        error = appError

        // Пометить последнее сообщение как ошибочное
        if let lastIndex = messages.lastIndex(where: { $0.id == assistantMessageId }) {
            let existingMessage = messages[lastIndex]
            let errorMessage = Message(
                id: existingMessage.id,
                role: .assistant,
                content: existingMessage.content,
                error: appError.errorDescription
            )
            messages[lastIndex] = errorMessage
        }
    }

    private func handleCompletion(_ completion: Subscribers.Completion<AppError>) {
        switch completion {
        case .finished:
            break
        case .failure(let appError):
            error = appError
        }
    }
}

// MARK: - Computed Properties

extension ChatViewModel {

    /// Проверить, есть ли сообщения
    var hasMessages: Bool {
        !messages.isEmpty
    }

    /// Проверить, можно ли отправить сообщение
    var canSend: Bool {
        !isLoading && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Проверить, можно ли отменить запрос
    var canCancel: Bool {
        isLoading || isStreaming
    }
}

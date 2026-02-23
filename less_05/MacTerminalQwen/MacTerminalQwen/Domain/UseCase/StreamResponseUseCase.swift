//
//  StreamResponseUseCase.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation
import Combine

/// Use Case для потокового получения ответа от LLM.
/// Предоставляет реактивный интерфейс для обновления UI в реальном времени.
protocol StreamResponseUseCaseProtocol {
    /// Получить поток ответов с метаданными
    /// - Parameters:
    ///   - messages: История сообщений
    ///   - settings: Настройки API
    ///   - apiKey: API ключ
    /// - Returns: Publisher с событиями стриминга
    func execute(
        messages: [Message],
        settings: ChatSettings,
        apiKey: String
    ) -> AnyPublisher<StreamEvent, AppError>
}

/// События стриминга для обновления UI.
enum StreamEvent {
    /// Начало стриминга
    case started

    /// Получен новый чанк текста
    case receivedChunk(String)

    /// Обновлены метрики
    case metricsUpdated(RequestMetrics)

    /// Стриминг завершён успешно
    case finished(finalMessage: Message, metrics: RequestMetrics)

    /// Произошла ошибка
    case failed(AppError)
}

/// Реализация Use Case для потокового получения ответов.
final class StreamResponseUseCase: StreamResponseUseCaseProtocol {

    private let repository: ChatRepositoryProtocol
    private let settingsService: SettingsService

    init(
        repository: ChatRepositoryProtocol,
        settingsService: SettingsService
    ) {
        self.repository = repository
        self.settingsService = settingsService
    }

    func execute(
        messages: [Message],
        settings: ChatSettings,
        apiKey: String
    ) -> AnyPublisher<StreamEvent, AppError> {
        // Валидация
        guard let validationError = validate(messages: messages, settings: settings) else {
            // Запуск стриминга
            return runStream(messages: messages, settings: settings, apiKey: apiKey)
        }

        // Возврат ошибки валидации
        return Fail(error: validationError).eraseToAnyPublisher()
    }

    // MARK: - Private

    private func validate(
        messages: [Message],
        settings: ChatSettings
    ) -> AppError? {
        guard let lastMessage = messages.last else {
            return .validation("Нет сообщений для отправки")
        }

        guard lastMessage.role == .user else {
            return .validation("Последнее сообщение должно быть от пользователя")
        }

        let validationErrors = settings.validate()
        if !validationErrors.isEmpty {
            return .validation(validationErrors.joined(separator: ", "))
        }

        return nil
    }

    private func runStream(
        messages: [Message],
        settings: ChatSettings,
        apiKey: String
    ) -> AnyPublisher<StreamEvent, AppError> {
        let startTime = Date()
        var accumulatedText = ""
        var chunkCount = 0

        // Создаём publisher из async stream
        return repository.sendChatRequest(
            messages: messages,
            settings: settings,
            apiKey: apiKey
        )
        .handleEvents(receiveSubscription: { _ in
            // Начало стриминга
        })
        .tryMap { chunk -> StreamEvent in
            accumulatedText += chunk
            chunkCount += 1

            // Считаем примерное количество токенов (1 токен ≈ 4 символа)
            let estimatedTokens = accumulatedText.count / 4
            let elapsed = Date().timeIntervalSince(startTime)
            let tokensPerSecond = elapsed > 0 ? Double(estimatedTokens) / elapsed : 0

            let metrics = RequestMetrics(
                completionTokens: estimatedTokens,
                duration: elapsed,
                tokensPerSecond: tokensPerSecond,
                modelName: settings.modelName
            )

            if chunkCount == 1 {
                return .started
            } else {
                return .receivedChunk(chunk)
            }
        }
        .mapError { error -> AppError in
            if let appError = error as? AppError {
                return appError
            } else if let networkError = error as? NetworkError {
                return .network(networkError)
            } else {
                return .unknown(error)
            }
        }
        .collect()
        .flatMap { events -> AnyPublisher<StreamEvent, AppError> in
            guard !events.isEmpty else {
                return Fail(error: .parsing("Пустой ответ от сервера")).eraseToAnyPublisher()
            }

            let finalText = events.dropFirst().compactMap { event -> String? in
                if case .receivedChunk(let text) = event {
                    return text
                }
                return nil
            }.joined()

            let finalMessage = Message.assistant(finalText)
            let finalMetrics = RequestMetrics(
                completionTokens: finalText.count / 4,
                duration: Date().timeIntervalSince(startTime),
                modelName: settings.modelName
            )

            var resultEvents: [StreamEvent] = [.started]
            resultEvents.append(contentsOf: events.dropFirst())
            resultEvents.append(.finished(finalMessage: finalMessage, metrics: finalMetrics))

            return Publishers.Sequence(sequence: resultEvents).eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }
}

// MARK: - Non-streaming Fallback

extension StreamResponseUseCase {

    /// Выполнить запрос без стриминга (для API без SSE поддержки)
    func executeNonStreaming(
        messages: [Message],
        settings: ChatSettings,
        apiKey: String
    ) -> AnyPublisher<StreamEvent, AppError> {
        let startTime = Date()

        return repository.sendNonStreamingRequest(
            messages: messages,
            settings: settings,
            apiKey: apiKey
        )
        .tryMap { response -> StreamEvent in
            let elapsed = Date().timeIntervalSince(startTime)
            let tokens = response.content.count / 4

            let metrics = RequestMetrics(
                promptTokens: response.usage?.promptTokens ?? 0,
                completionTokens: response.usage?.completionTokens ?? 0,
                totalTokens: response.usage?.totalTokens ?? 0,
                duration: elapsed,
                tokensPerSecond: elapsed > 0 ? Double(tokens) / elapsed : 0,
                modelName: settings.modelName
            )

            let message = Message.assistant(
                response.content,
                tokenCount: response.usage?.completionTokens
            )

            return .finished(finalMessage: message, metrics: metrics)
        }
        .mapError { error -> AppError in
            if let appError = error as? AppError {
                return appError
            } else if let networkError = error as? NetworkError {
                return .network(networkError)
            } else {
                return .unknown(error)
            }
        }
        .eraseToAnyPublisher()
    }
}

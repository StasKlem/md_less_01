//
//  SendMessageUseCase.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation
import Combine

/// Use Case для отправки сообщения и получения ответа от LLM.
/// Инкапсулирует бизнес-логику отправки запроса к API.
protocol SendMessageUseCaseProtocol {
    /// Отправить сообщение и получить полный ответ
    /// - Parameters:
    ///   - messages: История сообщений для контекста
    ///   - settings: Настройки API
    ///   - apiKey: API ключ для авторизации
    /// - Returns: Publisher с чанками ответа
    func execute(
        messages: [Message],
        settings: ChatSettings,
        apiKey: String
    ) -> AnyPublisher<String, AppError>
}

/// Реализация Use Case для отправки сообщений.
final class SendMessageUseCase: SendMessageUseCaseProtocol {
    
    private let repository: ChatRepositoryProtocol
    
    init(repository: ChatRepositoryProtocol) {
        self.repository = repository
    }
    
    func execute(
        messages: [Message],
        settings: ChatSettings,
        apiKey: String
    ) -> AnyPublisher<String, AppError> {
        // Валидация входных данных
        guard let userMessage = messages.last, userMessage.role == .user else {
            return Empty().eraseToAnyPublisher()
        }
        
        guard !userMessage.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Empty().eraseToAnyPublisher()
        }
        
        // Проверка настроек
        let validationErrors = settings.validate()
        guard validationErrors.isEmpty else {
            return Fail(error: AppError.validation(validationErrors.joined(separator: ", "))).eraseToAnyPublisher()
        }
        
        // Делегирование репозиторию
        return repository.sendChatRequest(
            messages: messages,
            settings: settings,
            apiKey: apiKey
        )
    }
}

//
//  LLMProvider.swift
//  SupportBot
//
//  Created by Stas Klem on 02.04.2026.
//

import Foundation

/// Протокол LLM провайдера
@MainActor
protocol LLMProvider {
    /// Название провайдера
    var providerName: String { get }
    
    /// Модель по умолчанию
    var defaultModel: String { get }
    
    /// Сгенерировать ответ
    /// - Parameters:
    ///   - prompt: Промпт для генерации
    ///   - model: Модель для использования (опционально)
    /// - Returns: Сгенерированный текст
    func generate(prompt: String, model: String?) async throws -> String
    
    /// Сгенерировать ответ с потоковой передачей
    /// - Parameters:
    ///   - prompt: Промпт для генерации
    ///   - model: Модель для использования
    ///   - onToken: Closure для каждого нового токена
    func generateStream(
        prompt: String,
        model: String?,
        onToken: @escaping (String) -> Void
    ) async throws -> String
}

/// Ошибка LLM провайдера
enum LLMError: LocalizedError {
    case apiError(String)
    case authenticationError(String)
    case rateLimitError(String)
    case networkError(String)
    case parsingError(String)
    case invalidResponse(String)
    
    var errorDescription: String? {
        switch self {
        case .apiError(let message):
            return "Ошибка API: \(message)"
        case .authenticationError(let message):
            return "Ошибка аутентификации: \(message)"
        case .rateLimitError(let message):
            return "Превышен лимит запросов: \(message)"
        case .networkError(let message):
            return "Ошибка сети: \(message)"
        case .parsingError(let message):
            return "Ошибка парсинга ответа: \(message)"
        case .invalidResponse(let message):
            return "Неверный ответ сервера: \(message)"
        }
    }
}

/// Конфигурация LLM провайдера
struct LLMProviderConfig {
    let provider: String
    let apiKey: String
    let baseURL: String
    let model: String
    let timeout: Int
    
    init(provider: String, apiKey: String, baseURL: String, model: String, timeout: Int) {
        self.provider = provider
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        self.timeout = timeout
    }
}

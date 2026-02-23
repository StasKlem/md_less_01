//
//  ChatResponse.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

/// DTO ответа от Chat API.
/// Соответствует формату OpenAI Chat Completions API.
struct ChatResponse: Codable {
    
    /// Уникальный идентификатор ответа
    let id: String
    
    /// Объект ответа (обычно "chat.completion")
    let object: String
    
    /// Timestamp создания
    let created: Int
    
    /// Название использованной модели
    let model: String
    
    /// Выборки ответов
    let choices: [Choice]
    
    /// Информация об использовании токенов
    let usage: Usage?
    
    // MARK: - Computed Properties
    
    /// Получить первый выбор (основной ответ)
    var firstChoice: Choice? {
        choices.first
    }
    
    /// Получить содержимое ответа
    var content: String {
        firstChoice?.message.content ?? ""
    }
    
    /// Получить количество токенов ответа
    var completionTokenCount: Int? {
        usage?.completionTokens
    }
}

/// DTO выбора ответа.
struct Choice: Codable {
    /// Индекс выбора
    let index: Int
    
    /// Сообщение с контентом
    let message: ResponseMessage
    
    /// Причина завершения (stop, length, и т.д.)
    let finish_reason: String?
}

/// DTO сообщения в ответе.
struct ResponseMessage: Codable {
    /// Роль отправителя
    let role: String
    
    /// Содержимое сообщения
    let content: String
}

/// DTO использования токенов.
struct Usage: Codable {
    /// Токены в запросе
    let prompt_tokens: Int
    
    /// Токены в ответе
    let completion_tokens: Int
    
    /// Общее количество токенов
    let total_tokens: Int
    
    // MARK: - Computed Properties
    
    var promptTokens: Int { prompt_tokens }
    var completionTokens: Int { completion_tokens }
    var totalTokens: Int { total_tokens }
}

// MARK: - Domain Mapping

extension ChatResponse {
    
    /// Преобразовать в domain-модель Message
    func toMessage() -> Message {
        Message.assistant(
            content,
            tokenCount: completionTokenCount
        )
    }
    
    /// Преобразовать в domain-модель RequestMetrics
    func toMetrics(duration: TimeInterval = 0) -> RequestMetrics {
        guard let usage = usage else {
            return RequestMetrics(modelName: model)
        }
        
        var metrics = RequestMetrics(
            promptTokens: usage.promptTokens,
            completionTokens: usage.completionTokens,
            totalTokens: usage.totalTokens,
            modelName: model
        )
        
        if duration > 0 {
            metrics.updateDuration(duration)
        }
        
        return metrics
    }
}

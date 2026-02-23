//
//  ChatRequest.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

/// DTO запроса к Chat API.
/// Соответствует формату OpenAI Chat Completions API.
struct ChatRequest: Codable {
    
    /// Название модели
    let model: String
    
    /// Сообщения для отправки
    let messages: [ChatMessageDTO]
    
    /// Температура генерации
    let temperature: Double?
    
    /// Максимальное количество токенов
    let max_tokens: Int?
    
    /// Top P для sampling
    let top_p: Double?
    
    /// Использовать потоковый режим
    let stream: Bool
    
    // MARK: - Initialization
    
    init(
        model: String,
        messages: [ChatMessageDTO],
        temperature: Double? = nil,
        max_tokens: Int? = nil,
        top_p: Double? = nil,
        stream: Bool = false
    ) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.max_tokens = max_tokens
        self.top_p = top_p
        self.stream = stream
    }
    
    // MARK: - Factory Method
    
    /// Создать запрос из domain-моделей
    static func from(
        messages: [Message],
        settings: ChatSettings
    ) -> ChatRequest {
        let dtoMessages = messages.map { message in
            ChatMessageDTO(role: message.role.rawValue, content: message.content)
        }
        
        return ChatRequest(
            model: settings.modelName,
            messages: dtoMessages,
            temperature: settings.temperature,
            max_tokens: settings.maxTokens,
            top_p: settings.topP,
            stream: settings.streamEnabled
        )
    }
}

/// DTO отдельного сообщения в запросе.
struct ChatMessageDTO: Codable {
    let role: String
    let content: String
    
    init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

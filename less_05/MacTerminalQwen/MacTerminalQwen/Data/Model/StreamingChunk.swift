//
//  StreamingChunk.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

/// DTO чанка потокового ответа.
/// Соответствует формату OpenAI Streaming API.
struct StreamingChunk: Codable {
    
    /// Уникальный идентификатор ответа
    let id: String
    
    /// Объект ответа (обычно "chat.completion.chunk")
    let object: String
    
    /// Timestamp создания
    let created: Int
    
    /// Название модели
    let model: String
    
    /// Выборки ответов
    let choices: [StreamChoice]
    
    // MARK: - Computed Properties
    
    /// Получить содержимое первого чанка
    var content: String? {
        choices.first?.delta?.content
    }
    
    /// Получить причину завершения
    var finishReason: String? {
        choices.first?.finish_reason
    }
    
    /// Проверить, является ли чанком завершения
    var isFinishChunk: Bool {
        finishReason != nil
    }
}

/// DTO выбора в потоковом ответе.
struct StreamChoice: Codable {
    /// Индекс выбора
    let index: Int
    
    /// Дельта (изменения) сообщения
    let delta: Delta?
    
    /// Причина завершения
    let finish_reason: String?
}

/// DTO дельты сообщения (изменения в потоковом режиме).
struct Delta: Codable {
    /// Роль отправителя (может быть в первом чанке)
    let role: String?
    
    /// Содержимое сообщения
    let content: String?
}

// MARK: - SSE Event

/// Представление SSE-события для парсинга.
struct SSEEvent {
    /// Тип события
    let event: String?

    /// Данные события
    let data: String

    /// Идентификатор события
    let id: String?

    /// Retry интервал
    let retry: Int?

    init(data: String, event: String? = nil, id: String? = nil, retry: Int? = nil) {
        self.event = event
        self.data = data
        self.id = id
        self.retry = retry
    }

    /// Парсить SSE-событие из строки
    static func parse(_ line: String) -> SSEEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        guard !trimmed.isEmpty else { return nil }
        
        if trimmed.hasPrefix("data: ") {
            return SSEEvent(data: String(trimmed.dropFirst(6)))
        } else if trimmed.hasPrefix("data:") {
            return SSEEvent(data: String(trimmed.dropFirst(5)))
        } else if trimmed.hasPrefix("event: ") {
            return SSEEvent(data: "", event: String(trimmed.dropFirst(7)))
        } else if trimmed.hasPrefix("id: ") {
            return SSEEvent(data: "", id: String(trimmed.dropFirst(4)))
        } else if trimmed.hasPrefix("retry: ") {
            if let retry = Int(String(trimmed.dropFirst(7))) {
                return SSEEvent(data: "", retry: retry)
            }
        }
        
        return nil
    }
}

// MARK: - StreamingChunk Extension

extension StreamingChunk {
    
    /// Парсить чанк из SSE-данных
    static func fromSSEData(_ data: String) -> StreamingChunk? {
        // Проверка на [DONE]
        if data.trimmingCharacters(in: .whitespaces) == "[DONE]" {
            return nil
        }
        
        guard let jsonData = data.data(using: .utf8) else {
            return nil
        }
        
        return try? JSONDecoder().decode(StreamingChunk.self, from: jsonData)
    }
}

//
//  Message.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

/// Роль участника диалога.
enum MessageRole: String, Codable, CaseIterable {
    /// Сообщение от пользователя
    case user
    /// Сообщение от ассистента (модели)
    case assistant
    /// Системное сообщение (инструкция для модели)
    case system
}

/// Entity сообщения в чате.
/// Неизменяемая структура, представляющая одно сообщение.
struct Message: Identifiable, Codable, Equatable {
    
    /// Уникальный идентификатор сообщения
    let id: UUID
    
    /// Роль отправителя
    let role: MessageRole
    
    /// Содержимое сообщения
    let content: String
    
    /// Временная метка создания
    let timestamp: Date
    
    /// Токены, использованные в сообщении (заполняется для ответов модели)
    let tokenCount: Int?
    
    /// Ошибка, если возникла при генерации ответа
    let error: String?
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        tokenCount: Int? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.tokenCount = tokenCount
        self.error = error
    }
    
    // MARK: - Convenience Initializers
    
    /// Создать сообщение от пользователя
    static func user(_ content: String) -> Message {
        Message(role: .user, content: content)
    }
    
    /// Создать сообщение от ассистента
    static func assistant(_ content: String, tokenCount: Int? = nil) -> Message {
        Message(role: .assistant, content: content, tokenCount: tokenCount)
    }
    
    /// Создать системное сообщение
    static func system(_ content: String) -> Message {
        Message(role: .system, content: content)
    }
    
    // MARK: - Computed Properties
    
    /// Проверить, является ли сообщение от пользователя
    var isUser: Bool {
        role == .user
    }
    
    /// Проверить, является ли сообщение от ассистента
    var isAssistant: Bool {
        role == .assistant
    }
    
    /// Проверить, является ли сообщение системным
    var isSystem: Bool {
        role == .system
    }
    
    /// Проверить наличие ошибки
    var hasError: Bool {
        error != nil
    }
}

// MARK: - Message Builder

/// Builder для постепенной сборки сообщения (полезно при стриминге).
final class MessageBuilder {
    
    private var id: UUID
    private var role: MessageRole
    private var content: String = ""
    private var tokenCount: Int?
    private var error: String?
    
    init(role: MessageRole = .assistant, id: UUID = UUID()) {
        self.id = id
        self.role = role
    }
    
    /// Добавить текст к сообщению
    func append(_ text: String) -> MessageBuilder {
        content.append(text)
        return self
    }
    
    /// Установить количество токенов
    func setTokenCount(_ count: Int) -> MessageBuilder {
        tokenCount = count
        return self
    }
    
    /// Установить ошибку
    func setError(_ error: String) -> MessageBuilder {
        self.error = error
        return self
    }
    
    /// Построить финальное сообщение
    func build() -> Message {
        Message(
            id: id,
            role: role,
            content: content,
            tokenCount: tokenCount,
            error: error
        )
    }
    
    /// Построить промежуточное сообщение (для стриминга)
    func buildPartial() -> Message {
        Message(
            id: id,
            role: role,
            content: content,
            tokenCount: nil,
            error: error
        )
    }
}

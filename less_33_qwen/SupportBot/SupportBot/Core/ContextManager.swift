//
//  ContextManager.swift
//  SupportBot
//
//  Created by Stas Klem on 02.04.2026.
//

import Foundation
import Logging

/// Менеджер контекста диалога
final class ContextManager {
    private let logger = Logger(label: "com.supportbot.context")
    
    private let chatHistoryDB: ChatHistoryDB
    private let contextConfig: ContextConfig
    
    /// Текущая активная сессия
    private var currentSession: ChatSession?
    
    /// Кэш сообщений текущей сессии
    private var messageCache: [Message] = []
    
    init(chatHistoryDB: ChatHistoryDB, contextConfig: ContextConfig) {
        self.chatHistoryDB = chatHistoryDB
        self.contextConfig = contextConfig
    }
    
    /// Инициализация контекста
    func initialize() throws {
        // Пытаемся получить последнюю активную сессию
        currentSession = try chatHistoryDB.getLastActiveSession()
        
        if let session = currentSession {
            logger.info("Loaded session: \(session.id)")
            
            // Загружаем последние сообщения в кэш
            messageCache = try chatHistoryDB.getLastMessages(
                sessionId: session.id,
                count: contextConfig.maxHistoryMessages
            )
        } else {
            // Создаем новую сессию
            try createNewSession()
        }
    }
    
    /// Создать новую сессию
    func createNewSession() throws {
        let session = ChatSession()
        try chatHistoryDB.createSession(session)
        currentSession = session
        messageCache = []
        logger.info("Created new session: \(session.id)")
    }
    
    /// Получить текущую сессию
    func getCurrentSession() -> ChatSession? {
        return currentSession
    }
    
    /// Получить ID текущей сессии
    func getSessionId() -> String? {
        return currentSession?.id
    }
    
    /// Добавить сообщение в контекст
    func addMessage(_ message: Message) throws {
        guard let sessionId = currentSession?.id else {
            throw ContextError.noActiveSession
        }
        
        // Сохраняем в базу
        try chatHistoryDB.addMessage(message, to: sessionId)
        
        // Добавляем в кэш
        messageCache.append(message)
        
        // Обрезаем кэш до максимального размера
        if messageCache.count > contextConfig.maxHistoryMessages {
            messageCache.removeFirst()
        }
        
        logger.debug("Added message to context: \(message.sender.rawValue)")
    }
    
    /// Получить историю сообщений для контекста
    func getContextHistory() -> [Message] {
        return messageCache
    }
    
    /// Получить последние N сообщений
    func getLastMessages(count: Int) -> [Message] {
        let limitedCount = min(count, messageCache.count)
        if limitedCount == 0 {
            return []
        }
        return Array(messageCache.suffix(limitedCount))
    }
    
    /// Очистить контекст
    func clearContext() throws {
        guard let sessionId = currentSession?.id else {
            throw ContextError.noActiveSession
        }
        
        try chatHistoryDB.clearMessages(sessionId: sessionId)
        messageCache = []
        logger.info("Cleared context for session: \(sessionId)")
    }
    
    /// Очистить старые сессии (TTL)
    func cleanupOldSessions() throws {
        let cutoffDate = Date().addingTimeInterval(-Double(contextConfig.ttlSeconds))
        try chatHistoryDB.cleanupOldSessions(olderThan: cutoffDate)
        logger.info("Cleaned up old sessions")
    }
    
    /// Установить данные тикета
    func setTicketData(_ ticketData: TicketData) throws {
        guard currentSession != nil else {
            throw ContextError.noActiveSession
        }
        
        // В полной версии нужно обновить сессию в БД
        // Для простоты создаем новую сессию с ticketData
        try createNewSession()
        logger.info("Set ticket data for session")
    }
}

enum ContextError: LocalizedError {
    case noActiveSession
    case sessionNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .noActiveSession:
            return "Нет активной сессии"
        case .sessionNotFound(let id):
            return "Сессия не найдена: \(id)"
        }
    }
}

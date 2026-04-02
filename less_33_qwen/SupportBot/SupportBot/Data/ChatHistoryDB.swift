//
//  ChatHistoryDB.swift
//  SupportBot
//
//  Created by Stas Klem on 02.04.2026.
//

import Foundation
import SQLite
import Logging

/// База данных истории чатов
final class ChatHistoryDB {
    private let logger = Logger(label: "com.supportbot.db")
    private var db: Connection?
    private let dbPath: String
    
    // Таблицы
    private let sessions = Table("chat_sessions")
    private let messages = Table("messages")
    
    // Колонки sessions
    private let sessionId = Expression<String>("id")
    private let createdAt = Expression<Date>("created_at")
    private let lastActivityAt = Expression<Date>("last_activity_at")
    
    // Колонки messages
    private let messageId = Expression<String>("id")
    private let messageSessionId = Expression<String>("session_id")
    private let role = Expression<String>("role")
    private let content = Expression<String>("content")
    private let messageTimestamp = Expression<Date>("created_at")
    
    init(dbPath: String) {
        self.dbPath = dbPath
    }
    
    /// Инициализация базы данных
    func initialize() throws {
        logger.info("Initializing database at: \(dbPath)")
        
        let dbDir = (dbPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dbDir, withIntermediateDirectories: true)
        
        db = try Connection(dbPath)
        try db!.run("PRAGMA journal_mode = WAL")
        
        try createSessionsTable()
        try createMessagesTable()
        
        logger.info("Database initialized successfully")
    }
    
    private func createSessionsTable() throws {
        try db!.run(sessions.create(ifNotExists: true) { t in
            t.column(sessionId, primaryKey: true)
            t.column(createdAt, defaultValue: Date())
            t.column(lastActivityAt, defaultValue: Date())
        })
        
        try db!.run(sessions.createIndex(lastActivityAt, ifNotExists: true))
    }
    
    private func createMessagesTable() throws {
        try db!.run(messages.create(ifNotExists: true) { t in
            t.column(messageId, primaryKey: true)
            t.column(messageSessionId)
            t.column(role)
            t.column(content)
            t.column(messageTimestamp, defaultValue: Date())
        })
        
        try db!.run(messages.createIndex(messageSessionId, ifNotExists: true))
        try db!.run(messages.createIndex(messageTimestamp, ifNotExists: true))
    }
    
    /// Создать новую сессию
    func createSession(_ session: ChatSession) throws {
        guard let db = db else { throw DBError.notInitialized }
        
        try db.run(sessions.insert(
            sessionId <- session.id,
            createdAt <- session.createdAt,
            lastActivityAt <- session.lastActivityAt
        ))
        
        logger.debug("Created session: \(session.id)")
    }
    
    /// Получить сессию по ID
    func getSession(id: String) throws -> ChatSession? {
        guard let db = db else { throw DBError.notInitialized }
        
        guard let row = try db.pluck(sessions.filter(sessionId == id)) else {
            return nil
        }
        
        return ChatSession(
            id: row[sessionId],
            createdAt: row[createdAt],
            lastActivityAt: row[lastActivityAt],
            ticketData: nil
        )
    }
    
    /// Обновить время активности сессии
    func updateSessionActivity(id: String) throws {
        guard let db = db else { throw DBError.notInitialized }
        try db.run(sessions.filter(sessionId == id).update(lastActivityAt <- Date()))
    }
    
    /// Получить последнюю активную сессию
    func getLastActiveSession() throws -> ChatSession? {
        guard let db = db else { throw DBError.notInitialized }
        
        let query = sessions.order(lastActivityAt.desc).limit(1)
        guard let row = try db.pluck(query) else {
            return nil
        }
        
        return try getSession(id: row[sessionId])
    }
    
    /// Добавить сообщение
    func addMessage(_ message: Message, to sessionId: String) throws {
        guard let db = db else { throw DBError.notInitialized }
        
        try db.run(messages.insert(
            messageId <- message.id.uuidString,
            messageSessionId <- sessionId,
            role <- message.sender.rawValue,
            content <- message.text,
            messageTimestamp <- message.timestamp
        ))
        
        try updateSessionActivity(id: sessionId)
        logger.debug("Added message to session \(sessionId): \(message.sender.rawValue)")
    }
    
    /// Получить последние N сообщений
    func getLastMessages(sessionId: String, count: Int) throws -> [Message] {
        guard let db = db else { throw DBError.notInitialized }
        
        let query = messages
            .filter(messageSessionId == sessionId)
            .order(messageTimestamp.desc)
            .limit(count)
        
        return try db.prepare(query).map { row in
            let sender = Sender(rawValue: row[role]) ?? .user
            return Message(
                id: UUID(uuidString: row[messageId]) ?? UUID(),
                text: row[content],
                sender: sender,
                timestamp: row[messageTimestamp]
            )
        }.reversed()
    }
    
    /// Удалить все сообщения сессии
    func clearMessages(sessionId: String) throws {
        guard let db = db else { throw DBError.notInitialized }
        try db.run(messages.filter(messageSessionId == sessionId).delete())
        logger.info("Cleared all messages for session: \(sessionId)")
    }
    
    /// Удалить сессию и все сообщения
    func deleteSession(id: String) throws {
        guard let db = db else { throw DBError.notInitialized }
        try db.run(sessions.filter(sessionId == id).delete())
        try db.run(messages.filter(messageSessionId == id).delete())
        logger.info("Deleted session: \(id)")
    }
    
    /// Очистить старые сессии
    func cleanupOldSessions(olderThan date: Date) throws {
        guard let db = db else { throw DBError.notInitialized }
        
        let oldSessions = try db.prepare(sessions.filter(lastActivityAt < date))
        var count = 0
        
        for session in oldSessions {
            try deleteSession(id: session[sessionId])
            count += 1
        }
        
        if count > 0 {
            logger.info("Cleaned up \(count) old sessions")
        }
    }
}

enum DBError: LocalizedError {
    case notInitialized
    case queryError(String)
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "База данных не инициализирована"
        case .queryError(let message):
            return "Ошибка запроса: \(message)"
        }
    }
}

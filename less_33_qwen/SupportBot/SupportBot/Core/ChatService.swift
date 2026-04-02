//
//  ChatService.swift
//  SupportBot
//
//  Created by Stas Klem on 02.04.2026.
//

import Foundation
import Logging

/// Сервис управления чатом
@MainActor
final class ChatService {
    private let logger = Logger(label: "com.supportbot.chat")
    
    private let ragService: RAGService
    private let contextManager: ContextManager
    private let chatHistoryDB: ChatHistoryDB
    
    init(
        ragService: RAGService,
        contextManager: ContextManager,
        chatHistoryDB: ChatHistoryDB
    ) {
        self.ragService = ragService
        self.contextManager = contextManager
        self.chatHistoryDB = chatHistoryDB
    }
    
    /// Инициализация сервиса
    func initialize() throws {
        try contextManager.initialize()
    }
    
    /// Обработать сообщение пользователя и получить ответ
    /// - Parameter userMessage: Сообщение пользователя
    /// - Returns: Ответ бота
    func processMessage(_ userMessage: String) async throws -> String {
        logger.info("Processing message: \(userMessage)")
        
        // Создаем сообщение пользователя
        let userMsg = Message(text: userMessage, sender: .user)
        
        // Сохраняем в контекст
        try contextManager.addMessage(userMsg)
        
        // Получаем историю для контекста
        let history = contextManager.getContextHistory()
        
        // Генерируем ответ через RAG
        let response = try await ragService.generateResponse(
            query: userMessage,
            history: history
        )
        
        // Создаем сообщение бота
        let botMsg = Message(text: response, sender: .bot)
        
        // Сохраняем в контекст
        try contextManager.addMessage(botMsg)
        
        return response
    }
    
    /// Получить историю чата
    func getChatHistory() -> [Message] {
        return contextManager.getContextHistory()
    }
    
    /// Очистить историю чата
    func clearChat() throws {
        try contextManager.clearContext()
        try contextManager.createNewSession()
        logger.info("Chat history cleared")
    }
    
    /// Создать новую сессию
    func newSession() throws {
        try contextManager.createNewSession()
    }
    
    /// Проверить, проиндексирована ли база знаний
    func isKnowledgeBaseIndexed() -> Bool {
        return ragService.checkIndexingStatus()
    }
    
    /// Индексировать базу знаний
    func indexKnowledgeBase(_ path: String) async throws -> Int {
        return try await ragService.indexKnowledgeBase(path)
    }
}

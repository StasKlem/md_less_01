//
//  SupportBotService.swift
//  SupportBot
//
//  Created by Stas Klem on 02.04.2026.
//

import Foundation
import Logging

/// Главный сервис приложения SupportBot
@MainActor
final class SupportBotService {
    private let logger = Logger(label: "com.supportbot.service")
    
    // Конфигурация
    private let config: BotConfig
    
    // Компоненты
    private let chatHistoryDB: ChatHistoryDB
    private let documentDB: DocumentDB
    private let vectorStore: VectorStore
    private let embeddingModel: EmbeddingModel
    private let llmProvider: LLMProvider
    private let chatService: ChatService
    private let ragService: RAGService
    private let contextManager: ContextManager
    
    // Состояние
    private var isInitialized = false
    private var isIndexing = false
    
    init(config: BotConfig) throws {
        self.config = config
        
        // Инициализация базы данных
        let dbPath = try ConfigManager.shared.getDatabasePath()
        self.chatHistoryDB = ChatHistoryDB(dbPath: dbPath)
        self.documentDB = DocumentDB(dbPath: dbPath.replacingOccurrences(of: ".db", with: "_documents.db"))
        self.vectorStore = VectorStore(dbPath: dbPath.replacingOccurrences(of: ".db", with: "_vectors.db"))
        
        // Инициализация embedding модели
        self.embeddingModel = OpenAIEmbedding(
            modelName: config.embeddings.model,
            dimension: config.embeddings.dimension,
            apiKey: config.llm.apiKey,
            baseURL: config.llm.baseURL,
            timeout: config.llm.timeout
        )
        
        // Инициализация LLM провайдера
        let llmConfig = LLMProviderConfig(
            provider: config.llm.provider,
            apiKey: config.llm.apiKey,
            baseURL: config.llm.baseURL,
            model: config.llm.model,
            timeout: config.llm.timeout
        )
        self.llmProvider = OpenAIProvider(config: llmConfig)
        
        // Инициализация RAG сервиса
        self.ragService = RAGService(
            documentDB: documentDB,
            vectorStore: vectorStore,
            embeddingModel: embeddingModel,
            llmProvider: llmProvider,
            ragConfig: config.rag
        )
        
        // Инициализация менеджера контекста
        self.contextManager = ContextManager(
            chatHistoryDB: chatHistoryDB,
            contextConfig: config.context
        )
        
        // Инициализация чат сервиса
        self.chatService = ChatService(
            ragService: ragService,
            contextManager: contextManager,
            chatHistoryDB: chatHistoryDB
        )
        
        logger.info("SupportBotService initialized")
    }
    
    /// Инициализация сервиса
    func initialize() throws {
        guard !isInitialized else {
            logger.warning("Service already initialized")
            return
        }
        
        logger.info("Initializing SupportBotService...")
        
        // Инициализация баз данных
        try chatHistoryDB.initialize()
        try documentDB.initialize()
        try vectorStore.initialize()
        
        // Инициализация чат сервиса
        try chatService.initialize()
        
        isInitialized = true
        logger.info("SupportBotService initialized successfully")
    }
    
    /// Индексировать базу знаний
    @MainActor
    func indexKnowledgeBase() async throws {
        guard !isIndexing else {
            logger.warning("Indexing already in progress")
            return
        }
        
        isIndexing = true
        defer { isIndexing = false }
        
        let kbPath = try ConfigManager.shared.getKnowledgeBasePath()
        logger.info("Indexing knowledge base at: \(kbPath)")
        
        let docCount = try await chatService.indexKnowledgeBase(kbPath)
        logger.info("Indexed \(docCount) documents")
    }
    
    /// Обработать сообщение и получить ответ
    @MainActor
    func processMessage(_ message: String) async throws -> String {
        guard isInitialized else {
            throw ServiceError.notInitialized
        }
        
        return try await chatService.processMessage(message)
    }
    
    /// Получить историю чата
    func getChatHistory() -> [Message] {
        return chatService.getChatHistory()
    }
    
    /// Очистить историю чата
    func clearChat() throws {
        try chatService.clearChat()
    }
    
    /// Создать новую сессию
    func newSession() throws {
        try chatService.newSession()
    }
    
    /// Проверить, проиндексирована ли база знаний
    func isKnowledgeBaseIndexed() -> Bool {
        return chatService.isKnowledgeBaseIndexed()
    }
    
    /// Получить версию приложения
    func getAppVersion() -> String {
        return config.app.version
    }
    
    /// Получить статус сервиса
    func getServiceStatus() -> ServiceStatus {
        return ServiceStatus(
            isInitialized: isInitialized,
            isIndexing: isIndexing,
            isKnowledgeBaseIndexed: isKnowledgeBaseIndexed(),
            sessionId: contextManager.getCurrentSession()?.id,
            messageCount: getChatHistory().count
        )
    }
}

/// Статус сервиса
struct ServiceStatus {
    let isInitialized: Bool
    let isIndexing: Bool
    let isKnowledgeBaseIndexed: Bool
    let sessionId: String?
    let messageCount: Int
}

enum ServiceError: LocalizedError {
    case notInitialized
    case indexingFailed(String)
    case generationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Сервис не инициализирован"
        case .indexingFailed(let message):
            return "Ошибка индексации: \(message)"
        case .generationFailed(let message):
            return "Ошибка генерации: \(message)"
        }
    }
}

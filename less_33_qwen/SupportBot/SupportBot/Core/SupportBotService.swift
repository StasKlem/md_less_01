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

    // Компоненты RAG
    private let chatHistoryDB: ChatHistoryDB
    private let documentDB: DocumentDB
    private let vectorStore: VectorStore
    private let embeddingModel: EmbeddingModel
    private let llmProvider: LLMProvider
    private let chatService: ChatService
    private let ragService: RAGService
    private let contextManager: ContextManager

    // Компоненты работы с файлами
    private let fileService: FileService
    private let projectAnalyzer: ProjectAnalyzer
    private let promptBuilder: PromptBuilder

    // Состояние
    private var isInitialized = false
    private var isIndexing = false

    init(config: BotConfig) throws {
        self.config = config
        self.promptBuilder = PromptBuilder()

        // Инициализация базы данных
        let dbPath = try ConfigManager.shared.getDatabasePath()
        self.chatHistoryDB = ChatHistoryDB(dbPath: dbPath)
        self.documentDB = DocumentDB(dbPath: dbPath.replacingOccurrences(of: ".db", with: "_documents.db"))
        self.vectorStore = VectorStore(dbPath: dbPath.replacingOccurrences(of: ".db", with: "_vectors.db"))

        // Инициализация файлового сервиса
        let projectRoot = config.storage.knowledgeBasePath.hasPrefix("./")
            ? String(config.storage.knowledgeBasePath.dropFirst(2).split(separator: "/").dropLast().joined(separator: "/"))
            : "."
        self.fileService = FileService(projectRoot: projectRoot)
        self.projectAnalyzer = ProjectAnalyzer(projectRoot: projectRoot, fileService: fileService)

        // Инициализация embedding модели
        switch config.embeddings.provider.lowercased() {
        case "openai":
            self.embeddingModel = OpenAIEmbedding(
                modelName: config.embeddings.model,
                dimension: config.embeddings.dimension,
                apiKey: config.llm.apiKey,
                baseURL: config.llm.baseURL,
                timeout: config.llm.timeout
            )
        case "local", "ollama", "lmstudio":
            let localBaseURL = config.embeddings.baseURL ?? "http://127.0.0.1:1234/v1"
            self.embeddingModel = LocalEmbedding(
                modelName: config.embeddings.model,
                dimension: config.embeddings.dimension,
                baseURL: localBaseURL,
                timeout: config.llm.timeout
            )
            logger.info("Используется локальная embedding модель: \(localBaseURL)")
        default:
            throw ServiceError.invalidConfig("Неизвестный провайдер эмбеддингов: \(config.embeddings.provider)")
        }

        // Инициализация LLM провайдера
        let llmConfig = LLMProviderConfig(
            provider: config.llm.provider,
            apiKey: config.llm.apiKey,
            baseURL: config.llm.baseURL,
            model: config.llm.model,
            timeout: config.llm.timeout
        )

        switch config.llm.provider.lowercased() {
        case "openai", "routerai":
            self.llmProvider = OpenAIProvider(config: llmConfig)
            logger.info("Используется LLM провайдер: \(config.llm.provider) (модель: \(config.llm.model))")
        case "local", "ollama":
            self.llmProvider = OpenAIProvider(config: llmConfig)
            logger.info("Используется локальная LLM: \(config.llm.baseURL)")
        default:
            throw ServiceError.invalidConfig("Неизвестный LLM провайдер: \(config.llm.provider)")
        }

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

    // MARK: - File Tools

    /// Выполнить инструмент
    func executeTool(tool: FileTool, arguments: [String]) async throws -> ToolResult {
        switch tool {
        case .read:
            return try executeReadTool(arguments)
        case .search:
            return try await executeSearchTool(arguments)
        case .create:
            return try await executeCreateTool(arguments)
        case .edit:
            return try executeEditTool(arguments)
        case .diff:
            return try executeDiffTool(arguments)
        case .analyze:
            return try executeAnalyzeTool()
        case .list:
            return try executeListTool(arguments)
        case .invariants:
            return try executeInvariantsTool()
        }
    }

    /// Прочитать файл
    private func executeReadTool(_ arguments: [String]) throws -> ToolResult {
        guard let path = arguments.first, !path.isEmpty else {
            return ToolResult(tool: .read, success: false, output: "Использование: /files <path>")
        }

        let content = try fileService.readFile(path: path)
        return ToolResult(tool: .read, success: true, output: content)
    }

    /// Поиск в файлах
    private func executeSearchTool(_ arguments: [String]) async throws -> ToolResult {
        guard let pattern = arguments.first, !pattern.isEmpty else {
            return ToolResult(tool: .search, success: false, output: "Использование: /search <pattern> [path]")
        }

        let paths = arguments.dropFirst()
        let result = try await fileService.searchInFiles(pattern: pattern, paths: Array(paths))
        return ToolResult(tool: .search, success: true, output: result)
    }

    /// Создать файл
    private func executeCreateTool(_ arguments: [String]) async throws -> ToolResult {
        guard let path = arguments.first, !path.isEmpty else {
            return ToolResult(tool: .create, success: false, output: "Использование: /create <path>")
        }

        // Для создания файла через LLM генерируем содержимое
        let fileType = (path as NSString).pathExtension
        let prompt = promptBuilder.buildFileContentPrompt(
            fileType: fileType,
            description: "Создать файл: \(path)"
        )

        let content = try await llmProvider.generate(prompt: prompt, model: nil)
        let result = try fileService.createFile(path: path, content: content)
        return ToolResult(tool: .create, success: true, output: result)
    }

    /// Изменить файл
    private func executeEditTool(_ arguments: [String]) throws -> ToolResult {
        guard arguments.count >= 3 else {
            return ToolResult(tool: .edit, success: false, output: "Использование: /edit <path> <old> <new>")
        }

        let path = arguments[0]
        let oldContent = arguments[1]
        let newContent = arguments[2]

        let result = try fileService.editFile(path: path, oldContent: oldContent, newContent: newContent)
        return ToolResult(tool: .edit, success: true, output: result)
    }

    /// Diff файла
    private func executeDiffTool(_ arguments: [String]) throws -> ToolResult {
        guard let path = arguments.first, !path.isEmpty else {
            return ToolResult(tool: .diff, success: false, output: "Использование: /diff <path>")
        }

        let content = try fileService.readFile(path: path)
        // Для простоты показываем содержимое (в полной версии — сравнение с git)
        var output = "📊 Содержимое файла: `\(path)`\n"
        output += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
        output += content
        return ToolResult(tool: .diff, success: true, output: output)
    }

    /// Анализ проекта
    private func executeAnalyzeTool() throws -> ToolResult {
        let result = try projectAnalyzer.analyze()
        return ToolResult(tool: .analyze, success: true, output: result)
    }

    /// Список файлов
    private func executeListTool(_ arguments: [String]) throws -> ToolResult {
        let path = arguments.first ?? "."
        let result = try fileService.listDirectory(path: path)
        return ToolResult(tool: .list, success: true, output: result)
    }

    /// Проверка инвариантов
    private func executeInvariantsTool() throws -> ToolResult {
        let result = try projectAnalyzer.checkInvariants()
        return ToolResult(tool: .invariants, success: true, output: result)
    }

    /// Обработать запрос через файлового ассистента
    func processFileAssistantQuery(_ query: String) async throws -> String {
        let prompt = promptBuilder.buildFileAssistantPrompt(query: query)
        return try await llmProvider.generate(prompt: prompt, model: nil)
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
    case invalidConfig(String)
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Сервис не инициализирован"
        case .indexingFailed(let message):
            return "Ошибка индексации: \(message)"
        case .generationFailed(let message):
            return "Ошибка генерации: \(message)"
        case .invalidConfig(let message):
            return "Ошибка конфигурации: \(message)"
        }
    }
}

//
//  RAGService.swift
//  SupportBot
//
//  Created by Stas Klem on 02.04.2026.
//

import Foundation
import Logging

/// Сервис RAG (Retrieval-Augmented Generation)
@MainActor
final class RAGService {
    private let logger = Logger(label: "com.supportbot.rag")
    
    private let documentDB: DocumentDB
    private let vectorStore: VectorStore
    private let embeddingModel: EmbeddingModel
    private let llmProvider: LLMProvider
    private let ragConfig: RAGConfig
    private let promptBuilder: PromptBuilder
    
    private var isIndexed = false
    
    init(
        documentDB: DocumentDB,
        vectorStore: VectorStore,
        embeddingModel: EmbeddingModel,
        llmProvider: LLMProvider,
        ragConfig: RAGConfig
    ) {
        self.documentDB = documentDB
        self.vectorStore = vectorStore
        self.embeddingModel = embeddingModel
        self.llmProvider = llmProvider
        self.ragConfig = ragConfig
        self.promptBuilder = PromptBuilder()
    }
    
    /// Индексировать документы
    /// - Parameter knowledgeBasePath: Путь к базе знаний
    @discardableResult
    func indexKnowledgeBase(_ knowledgeBasePath: String) async throws -> Int {
        logger.info("Starting knowledge base indexing...")
        
        let indexer = DocumentIndexer(documentDB: documentDB, ragConfig: ragConfig)
        let docCount = try indexer.indexDirectory(knowledgeBasePath)
        
        // Создаем эмбеддинги для всех чанков
        let chunks = try documentDB.getAllChunks()
        logger.info("Creating embeddings for \(chunks.count) chunks...")
        
        var embeddingsCreated = 0
        for chunk in chunks {
            // Проверяем, есть ли уже эмбеддинг
            if let _ = try? vectorStore.getEmbedding(chunkId: chunk.id) {
                continue
            }
            
            // Создаем эмбеддинг
            let vector = try await embeddingModel.embed(text: chunk.content)
            let embedding = Embedding(
                id: UUID().uuidString,
                chunkId: chunk.id,
                vector: vector,
                dimension: embeddingModel.dimension,
                model: embeddingModel.modelName
            )
            
            try vectorStore.saveEmbedding(embedding)
            embeddingsCreated += 1
            
            // Логгируем прогресс
            if embeddingsCreated % 10 == 0 {
                logger.debug("Created \(embeddingsCreated) embeddings...")
            }
        }
        
        isIndexed = true
        logger.info("Indexing complete: \(docCount) documents, \(embeddingsCreated) embeddings")
        return docCount
    }
    
    /// Найти релевантные фрагменты
    /// - Parameter query: Запрос пользователя
    /// - Returns: Массив релевантных контекстов
    func findRelevantContext(query: String) async throws -> [RAGContext] {
        logger.debug("Finding relevant context for: \(query)")
        
        // Создаем эмбеддинг запроса
        let queryVector = try await embeddingModel.embed(text: query)
        
        // Ищем похожие векторы
        let results = try vectorStore.searchSimilar(
            queryVector: queryVector,
            topK: ragConfig.topK,
            minScore: ragConfig.minScore
        )
        
        logger.debug("Found \(results.count) relevant chunks")
        
        // Преобразуем в RAGContext
        var contexts: [RAGContext] = []
        for (embedding, score) in results {
            guard let chunk = try? documentDB.getChunk(id: embedding.chunkId) else {
                continue
            }
            
            // Получаем информацию о документе для источника
            let source = (try? documentDB.getDocument(id: chunk.documentId))?.title ?? "Неизвестно"
            
            let context = RAGContext(
                content: chunk.content,
                source: source,
                score: score
            )
            contexts.append(context)
        }
        
        return contexts
    }
    
    /// Сгенерировать ответ на запрос
    /// - Parameters:
    ///   - query: Запрос пользователя
    ///   - history: История диалога
    /// - Returns: Сгенерированный ответ
    func generateResponse(query: String, history: [Message]) async throws -> String {
        logger.info("Generating response for query: \(query)")

        // Находим релевантный контекст
        let context = try await findRelevantContext(query: query)
        
        // Логируем найденный контекст
        if context.isEmpty {
            logger.warning("⚠️ RAG: Контекст не найден для запроса: \(query)")
        } else {
            logger.info("✅ RAG: Найдено \(context.count) релевантных фрагментов:")
            for (i, item) in context.enumerated() {
                logger.info("   [\(i+1)] \(item.source) (score: \(String(format: "%.3f", item.score)))")
                logger.info("       \(item.content.prefix(100).replacingOccurrences(of: "\n", with: " "))...")
            }
        }

        // Строим промпт
        let prompt = promptBuilder.buildPrompt(
            query: query,
            context: context,
            history: history
        )

        logger.debug("Prompt length: \(prompt.count) characters")

        // Генерируем ответ через LLM
        let response = try await llmProvider.generate(prompt: prompt, model: nil)

        logger.info("Response generated successfully")
        return response
    }
    
    /// Проверить, проиндексирована ли база знаний
    func checkIndexingStatus() -> Bool {
        return isIndexed
    }
    
    /// Переиндексировать базу знаний
    @discardableResult
    func reindexKnowledgeBase(_ knowledgeBasePath: String) async throws -> Int {
        logger.info("Starting reindexing...")
        
        // Очищаем векторное хранилище
        try vectorStore.clearAll()
        
        // Очищаем базу документов
        try documentDB.clearAllDocuments()
        
        // Индексируем заново
        return try await indexKnowledgeBase(knowledgeBasePath)
    }
}

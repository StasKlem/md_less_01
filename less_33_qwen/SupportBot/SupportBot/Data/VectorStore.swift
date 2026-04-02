//
//  VectorStore.swift
//  SupportBot
//
//  Created by Stas Klem on 02.04.2026.
//

import Foundation
import SQLite
import Logging

/// Векторное хранилище для эмбеддингов
final class VectorStore {
    private let logger = Logger(label: "com.supportbot.vectorstore")
    private var db: Connection?
    private let dbPath: String
    
    // Таблица
    private let embeddings = Table("embeddings")
    
    // Колонки
    private let embeddingId = Expression<String>("id")
    private let chunkId = Expression<String>("chunk_id")
    private let vector = Expression<String>("vector")
    private let dimension = Expression<Int>("dimension")
    private let model = Expression<String>("model")
    private let createdAt = Expression<Date>("created_at")
    
    init(dbPath: String) {
        self.dbPath = dbPath
    }
    
    /// Инициализация хранилища
    func initialize() throws {
        logger.info("Initializing VectorStore at: \(dbPath)")
        
        let dbDir = (dbPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dbDir, withIntermediateDirectories: true)
        
        db = try Connection(dbPath)
        try db!.run("PRAGMA journal_mode = WAL")
        
        try createTable()
        
        logger.info("VectorStore initialized successfully")
    }
    
    private func createTable() throws {
        try db!.run(embeddings.create(ifNotExists: true) { t in
            t.column(embeddingId, primaryKey: true)
            t.column(chunkId)
            t.column(vector)
            t.column(dimension)
            t.column(model)
            t.column(createdAt, defaultValue: Date())
        })
        
        try db!.run(embeddings.createIndex(chunkId, ifNotExists: true))
    }
    
    /// Сохранить эмбеддинг
    func saveEmbedding(_ embedding: Embedding) throws {
        guard let db = db else { throw DBError.notInitialized }
        
        let vectorJSON = try JSONSerialization.data(withJSONObject: embedding.vector)
        let vectorString = String(data: vectorJSON, encoding: .utf8)!
        
        // Сначала пробуем обновить, если не существует - вставляем
        let query = embeddings.filter(chunkId == embedding.chunkId)
        if (try? db.pluck(query)) != nil {
            try db.run(query.update(
                vector <- vectorString,
                dimension <- embedding.dimension,
                model <- embedding.model,
                createdAt <- embedding.createdAt
            ))
        } else {
            try db.run(embeddings.insert(
                embeddingId <- embedding.id,
                chunkId <- embedding.chunkId,
                vector <- vectorString,
                dimension <- embedding.dimension,
                model <- embedding.model,
                createdAt <- embedding.createdAt
            ))
        }
        
        logger.debug("Saved embedding for chunk: \(embedding.chunkId)")
    }
    
    /// Получить все эмбеддинги
    func getAllEmbeddings() throws -> [Embedding] {
        guard let db = db else { throw DBError.notInitialized }
        
        return try db.prepare(embeddings).compactMap { row in
            let vectorString = row[vector]
            guard let vectorData = vectorString.data(using: .utf8),
                  let vectorArray = try? JSONSerialization.jsonObject(with: vectorData) as? [Double] else {
                return nil
            }
            
            return Embedding(
                id: row[embeddingId],
                chunkId: row[chunkId],
                vector: vectorArray,
                dimension: row[dimension],
                model: row[model],
                createdAt: row[createdAt]
            )
        }
    }
    
    /// Получить эмбеддинг по ID чанка
    func getEmbedding(chunkId: String) throws -> Embedding? {
        guard let db = db else { throw DBError.notInitialized }
        
        guard let row = try db.pluck(embeddings.filter(self.chunkId == chunkId)) else {
            return nil
        }

        let vectorString = row[vector]
        guard let vectorData = vectorString.data(using: .utf8),
              let vectorArray = try? JSONSerialization.jsonObject(with: vectorData) as? [Double] else {
            return nil
        }

        return Embedding(
            id: row[embeddingId],
            chunkId: chunkId,
            vector: vectorArray,
            dimension: row[dimension],
            model: row[model],
            createdAt: row[createdAt]
        )
    }
    
    /// Очистить все эмбеддинги
    func clearAll() throws {
        guard let db = db else { throw DBError.notInitialized }
        try db.run(embeddings.delete())
        logger.info("Cleared all embeddings")
    }
    
    /// Поиск наиболее похожих эмбеддингов
    func searchSimilar(
        queryVector: [Double],
        topK: Int = 5,
        minScore: Double = 0.0
    ) throws -> [(embedding: Embedding, score: Double)] {
        let allEmbeddings = try getAllEmbeddings()
        var results: [(Embedding, Double)] = []
        
        let normalizedQuery = normalize(queryVector)
        
        for embedding in allEmbeddings {
            let normalizedEmbedding = embedding.normalized
            let score = cosineSimilarity(a: normalizedQuery, b: normalizedEmbedding)
            
            if score >= minScore {
                results.append((embedding, score))
            }
        }
        
        results.sort { $0.1 > $1.1 }
        return Array(results.prefix(topK))
    }
    
    /// Косинусное сходство
    private func cosineSimilarity(a: [Double], b: [Double]) -> Double {
        guard a.count == b.count && a.count > 0 else { return 0 }
        
        var dotProduct: Double = 0
        var magnitudeA: Double = 0
        var magnitudeB: Double = 0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            magnitudeA += a[i] * a[i]
            magnitudeB += b[i] * b[i]
        }
        
        magnitudeA = sqrt(magnitudeA)
        magnitudeB = sqrt(magnitudeB)
        
        guard magnitudeA > 0 && magnitudeB > 0 else { return 0 }
        
        return dotProduct / (magnitudeA * magnitudeB)
    }
    
    /// Нормализация вектора
    private func normalize(_ vector: [Double]) -> [Double] {
        let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }
}

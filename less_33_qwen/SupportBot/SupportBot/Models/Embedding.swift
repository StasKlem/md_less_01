//
//  Embedding.swift
//  SupportBot
//
//  Created by Stas Klem on 02.04.2026.
//

import Foundation

/// Векторное представление (эмбеддинг)
struct Embedding: Codable {
    let id: String
    let chunkId: String
    let vector: [Double]
    let dimension: Int
    let model: String
    let createdAt: Date
    
    init(
        id: String = UUID().uuidString,
        chunkId: String,
        vector: [Double],
        dimension: Int,
        model: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.chunkId = chunkId
        self.vector = vector
        self.dimension = dimension
        self.model = model
        self.createdAt = createdAt
    }
    
    /// Нормализованный вектор (для косинусного сходства)
    var normalized: [Double] {
        let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }
}

/// Результат поиска эмбеддингов
struct EmbeddingSearchResult: Codable {
    let embedding: Embedding
    let chunk: Chunk
    let score: Double
    
    init(embedding: Embedding, chunk: Chunk, score: Double) {
        self.embedding = embedding
        self.chunk = chunk
        self.score = score
    }
}

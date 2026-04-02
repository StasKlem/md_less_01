//
//  LocalEmbedding.swift
//  SupportBot
//
//  Created by Stas Klem on 02.04.2026.
//

import Foundation
import AsyncHTTPClient
import NIOCore
import NIOPosix
import Logging

/// Локальная модель эмбеддингов (совместимая с OpenAI API)
final class LocalEmbedding: EmbeddingModel {
    private let logger = Logger(label: "com.supportbot.local.embedding")
    
    let modelName: String
    let dimension: Int
    
    private let baseURL: String
    private let timeout: Int
    
    private let eventLoopGroup: EventLoopGroup
    
    init(
        modelName: String = "text-embedding-bge-m3",
        dimension: Int = 1024,
        baseURL: String = "http://127.0.0.1:1234/v1",
        timeout: Int = 30
    ) {
        self.modelName = modelName
        self.dimension = dimension
        self.baseURL = baseURL
        self.timeout = timeout
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }
    
    deinit {
        try? eventLoopGroup.syncShutdownGracefully()
    }
    
    /// Создать эмбеддинг для текста
    func embed(text: String) async throws -> [Double] {
        let embeddings = try await embed(texts: [text])
        guard let embedding = embeddings.first else {
            throw EmbeddingError.invalidResponse("Пустой ответ от API")
        }
        return embedding
    }
    
    /// Создать эмбеддинги для нескольких текстов
    func embed(texts: [String]) async throws -> [[Double]] {
        guard !texts.isEmpty else {
            return []
        }
        
        logger.debug("Creating embeddings for \(texts.count) texts using local API")
        
        // Подготовка запроса
        let requestBody = LocalEmbeddingRequest(
            model: modelName,
            input: texts,
            encoding_format: "float"
        )
        
        let jsonData = try JSONEncoder().encode(requestBody)
        
        // Создание HTTP запроса
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
        
        defer {
            httpClient.shutdown()
        }
        
        var request = HTTPClientRequest(url: "\(baseURL)/embeddings")
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/json")
        request.body = .bytes(ByteBuffer(data: jsonData))
        
        logger.debug("Sending request to: \(baseURL)/embeddings")
        
        // Отправка запроса
        let response = try await httpClient.execute(request, timeout: .seconds(Int64(timeout)))
        
        // Проверка статуса
        guard response.status == .ok else {
            let errorBody = try await response.body.collect(upTo: 1024 * 1024)
            let errorText = String(buffer: errorBody)
            logger.error("Local Embedding API error: \(errorText)")
            throw EmbeddingError.apiError("Status: \(response.status), Body: \(errorText)")
        }
        
        // Парсинг ответа
        let responseBody = try await response.body.collect(upTo: 10 * 1024 * 1024)
        let responseString = String(buffer: responseBody)
        
        logger.debug("Received response: \(responseString.prefix(200))...")
        
        let embeddingResponse = try JSONDecoder().decode(LocalEmbeddingResponse.self, from: Data(responseString.utf8))
        
        // Извлекаем векторы в правильном порядке
        var embeddings: [[Double]] = Array(repeating: [], count: embeddingResponse.data.count)
        for item in embeddingResponse.data {
            guard item.index < embeddings.count else { continue }
            embeddings[item.index] = item.embedding
        }
        
        logger.debug("Received \(embeddings.count) embeddings")
        return embeddings
    }
}

// MARK: - Модели запроса/ответа

struct LocalEmbeddingRequest: Codable {
    let model: String
    let input: [String]
    let encoding_format: String
}

struct LocalEmbeddingResponse: Codable {
    let object: String
    let data: [LocalEmbeddingData]
    let model: String
    let usage: LocalUsageInfo?
}

struct LocalEmbeddingData: Codable {
    let object: String
    let embedding: [Double]
    let index: Int
}

struct LocalUsageInfo: Codable {
    let prompt_tokens: Int
    let total_tokens: Int
}

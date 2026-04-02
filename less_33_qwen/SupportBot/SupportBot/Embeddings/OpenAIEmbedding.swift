//
//  OpenAIEmbedding.swift
//  SupportBot
//
//  Created by Stas Klem on 02.04.2026.
//

import Foundation
import AsyncHTTPClient
import NIOCore
import NIOPosix
import Logging

/// OpenAI Embedding модель
final class OpenAIEmbedding: EmbeddingModel {
    private let logger = Logger(label: "com.supportbot.openai.embedding")
    
    let modelName: String
    let dimension: Int
    
    private let apiKey: String
    private let baseURL: String
    private let timeout: Int
    
    private let eventLoopGroup: EventLoopGroup
    
    init(modelName: String = "text-embedding-3-small", dimension: Int = 1536, apiKey: String, baseURL: String = "https://api.openai.com/v1", timeout: Int = 30) {
        self.modelName = modelName
        self.dimension = dimension
        self.apiKey = apiKey
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
        
        logger.debug("Creating embeddings for \(texts.count) texts")
        
        // Подготовка запроса
        let requestBody = OpenAIEmbeddingRequest(
            model: modelName,
            input: texts,
            encoding_format: "float"
        )
        
        let jsonData = try JSONEncoder().encode(requestBody)
        
        // Создание HTTP запроса
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
        
        defer {
            try? httpClient.shutdown()
        }
        
        var request = HTTPClientRequest(url: "\(baseURL)/embeddings")
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/json")
        request.headers.add(name: "Authorization", value: "Bearer \(apiKey)")
        request.body = .bytes(ByteBuffer(data: jsonData))
        
        // Отправка запроса
        let response = try await httpClient.execute(request, timeout: .seconds(Int64(timeout)))
        
        // Проверка статуса
        guard response.status == .ok else {
            let errorBody = try await response.body.collect(upTo: 1024 * 1024)
            let errorText = String(buffer: errorBody)
            logger.error("OpenAI API error: \(errorText)")
            throw EmbeddingError.apiError("Status: \(response.status), Body: \(errorText)")
        }
        
        // Парсинг ответа
        let responseBody = try await response.body.collect(upTo: 10 * 1024 * 1024)
        let responseString = String(buffer: responseBody)
        
        let embeddingResponse = try JSONDecoder().decode(OpenAIEmbeddingResponse.self, from: Data(responseString.utf8))
        
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

struct OpenAIEmbeddingRequest: Codable {
    let model: String
    let input: [String]
    let encoding_format: String
}

struct OpenAIEmbeddingResponse: Codable {
    let object: String
    let data: [EmbeddingData]
    let model: String
    let usage: UsageInfo
}

struct EmbeddingData: Codable {
    let object: String
    let embedding: [Double]
    let index: Int
}

struct UsageInfo: Codable {
    let prompt_tokens: Int
    let total_tokens: Int
}

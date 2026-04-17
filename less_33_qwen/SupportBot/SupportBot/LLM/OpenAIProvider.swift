//
//  OpenAIProvider.swift
//  SupportBot
//
//  Created by Stas Klem on 02.04.2026.
//

import Foundation
import AsyncHTTPClient
import NIOCore
import NIOPosix
import Logging

/// OpenAI LLM провайдер
final class OpenAIProvider: LLMProvider {
    private let logger = Logger(label: "com.supportbot.openai.llm")
    
    let providerName: String = "OpenAI"
    let defaultModel: String
    
    private let apiKey: String
    private let baseURL: String
    private let timeout: Int
    
    private let eventLoopGroup: EventLoopGroup
    
    init(config: LLMProviderConfig) {
        self.defaultModel = config.model
        self.apiKey = "sk-1yDhC2RWnMX_RUo2F3FBtLKgBOKvoUFb"//config.apiKey
        self.baseURL = config.baseURL
        self.timeout = config.timeout
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }
    
    deinit {
        try? eventLoopGroup.syncShutdownGracefully()
    }
    
    /// Сгенерировать ответ
    func generate(prompt: String, model: String?) async throws -> String {
        let modelToUse = model ?? defaultModel
        logger.info("Generating response with model: \(modelToUse)")
        
        // Подготовка запроса
        let requestBody = OpenAIChatRequest(
            model: modelToUse,
            messages: [
                OpenAIChatMessage(role: "user", content: prompt)
            ],
            temperature: 0.7,
            max_tokens: 1024
        )
        
        let jsonData = try JSONEncoder().encode(requestBody)
        
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
        
        defer {
            httpClient.shutdown()
        }
        
        var request = HTTPClientRequest(url: "\(baseURL)/chat/completions")
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
            
            if response.status == .unauthorized {
                throw LLMError.authenticationError("Неверный API ключ")
            } else if response.status == .tooManyRequests {
                throw LLMError.rateLimitError("Превышен лимит запросов")
            } else {
                throw LLMError.apiError("Status: \(response.status), Body: \(errorText)")
            }
        }
        
        // Парсинг ответа
        let responseBody = try await response.body.collect(upTo: 10 * 1024 * 1024)
        let responseString = String(buffer: responseBody)
        
        let chatResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: Data(responseString.utf8))
        
        guard let choice = chatResponse.choices.first,
              let content = choice.message.content else {
            throw LLMError.invalidResponse("Пустой ответ от API")
        }
        
        logger.debug("Generated response: \(content.prefix(100))...")
        return content
    }
    
    /// Сгенерировать ответ с потоковой передачей
    func generateStream(
        prompt: String,
        model: String?,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        // Для простоты реализуем через обычный запрос
        // В полной версии нужно использовать SSE streaming
        return try await generate(prompt: prompt, model: model)
    }
}

// MARK: - Модели запроса/ответа

struct OpenAIChatRequest: Codable {
    let model: String
    let messages: [OpenAIChatMessage]
    let temperature: Double
    let max_tokens: Int
}

struct OpenAIChatMessage: Codable {
    let role: String
    let content: String?
}

struct OpenAIChatResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [ChatChoice]
    let usage: UsageInfo?
}

struct ChatChoice: Codable {
    let index: Int
    let message: ChatMessage
    let finish_reason: String?
}

struct ChatMessage: Codable {
    let role: String
    let content: String?
}

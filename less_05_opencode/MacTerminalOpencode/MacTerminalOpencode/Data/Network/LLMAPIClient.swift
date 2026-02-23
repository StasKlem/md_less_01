//
//  LLMAPIClient.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

/// Protocol for LLM API operations
protocol LLMAPIClientProtocol {
    func sendMessage(
        messages: [[String: String]],
        settings: LLMSettings,
        apiKey: String?
    ) async throws -> String
    
    func streamMessage(
        messages: [[String: String]],
        settings: LLMSettings,
        apiKey: String?,
        onChunk: @escaping (String) -> Void
    ) async throws
    
    func fetchAvailableModels(settings: LLMSettings, apiKey: String?) async throws -> [String]
}

/// Client for OpenAI-compatible LLM APIs (Ollama, LM Studio, etc.)
final class LLMAPIClient: LLMAPIClientProtocol {
    
    private let networkManager: NetworkManagerProtocol
    private let sseParser: SSEParser
    
    init(networkManager: NetworkManagerProtocol = NetworkManager()) {
        self.networkManager = networkManager
        self.sseParser = SSEParser()
    }
    
    /// Sends a non-streaming message request
    func sendMessage(
        messages: [[String: String]],
        settings: LLMSettings,
        apiKey: String?
    ) async throws -> String {
        guard let url = settings.chatCompletionsURL else {
            throw AppError.network(.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
//        request.setValue("application/json", forHTTPHeaderField: "Content")
        
        if let apiKey = apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        let body: [String: Any] = [
            "model": settings.modelName,
            "messages": messages,
            "temperature": settings.temperature,
            "max_tokens": settings.maxTokens,
            "stream": false
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let response: ChatCompletionResponse = try await networkManager.performRequest(request)
        
        return response.choices.first?.message.content ?? ""
    }
    
    /// Sends a streaming message request with callback for each chunk
    func streamMessage(
        messages: [[String: String]],
        settings: LLMSettings,
        apiKey: String?,
        onChunk: @escaping (String) -> Void
    ) async throws {
        guard let url = settings.chatCompletionsURL else {
            throw AppError.network(.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let apiKey = apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        let body: [String: Any] = [
            "model": settings.modelName,
            "messages": messages,
            "temperature": settings.temperature,
            "max_tokens": settings.maxTokens,
            "stream": true
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        await sseParser.reset()
        
        let stream = networkManager.performStreamingRequest(request)
        
        for try await data in stream {
            let chunks = await sseParser.parse(data)
            
            for chunk in chunks {
                if let content = chunk.deltaContent {
                    onChunk(content)
                }
            }
        }
    }
    
    /// Fetches available models from the API
    func fetchAvailableModels(settings: LLMSettings, apiKey: String?) async throws -> [String] {
        guard let url = settings.modelsURL else {
            throw AppError.network(.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        if let apiKey = apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        let response: ModelsResponse = try await networkManager.performRequest(request)
        
        return response.data.map { $0.id }
    }
}

private struct ChatCompletionResponse: Decodable {
    let id: String
    let choices: [ChatChoice]
}

private struct ChatChoice: Decodable {
    let message: ChatMessage
}

private struct ChatMessage: Decodable {
    let role: String
    let content: String
}

private struct ModelsResponse: Decodable {
    let data: [ModelData]
}

private struct ModelData: Decodable {
    let id: String
}

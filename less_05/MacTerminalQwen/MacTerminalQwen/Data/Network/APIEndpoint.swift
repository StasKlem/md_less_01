//
//  APIEndpoint.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

/// Конфигурация API эндпоинтов.
enum APIEndpoint {
    
    /// Chat completions эндпоинт
    case chatCompletions
    
    /// Models эндпоинт (для получения списка моделей)
    case models
    
    /// Custom эндпоинт
    case custom(String)
    
    // MARK: - Path
    
    /// Получить путь эндпоинта
    var path: String {
        switch self {
        case .chatCompletions:
            return "/chat/completions"
        case .models:
            return "/models"
        case .custom(let path):
            return path.hasPrefix("/") ? path : "/\(path)"
        }
    }
}

// MARK: - URL Building

extension APIEndpoint {
    
    /// Построить полный URL на основе базового
    func buildURL(baseURL: String) -> URL? {
        guard !baseURL.isEmpty else { return nil }
        
        // Нормализация baseURL
        let normalizedBase = baseURL.hasSuffix("/")
            ? String(baseURL.dropLast())
            : baseURL
        
        let fullString = normalizedBase + path
        
        return URL(string: fullString)
    }
    
    /// Построить URL из настроек
    func buildURL(from settings: ChatSettings) -> URL? {
        if let customURL = URL(string: settings.chatEndpoint),
           settings.chatEndpoint.hasPrefix("http") {
            return customURL
        }
        
        return buildURL(baseURL: settings.serverURL)
    }
}

// MARK: - Request Building

extension APIEndpoint {
    
    /// Построить URLRequest для запроса
    func buildRequest(
        baseURL: String,
        method: String = "POST",
        body: Data? = nil,
        apiKey: String?,
        contentType: String = "application/json"
    ) -> URLRequest? {
        guard let url = buildURL(baseURL: baseURL) else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        
        // Заголовки
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Авторизация
        if let apiKey = apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        return request
    }
    
    /// Построить URLRequest для SSE стриминга
    func buildStreamingRequest(
        baseURL: String,
        body: Data,
        apiKey: String?
    ) -> URLRequest? {
        buildRequest(
            baseURL: baseURL,
            method: "POST",
            body: body,
            apiKey: apiKey,
            contentType: "application/json"
        )
    }
}

// MARK: - Content Type

extension APIEndpoint {
    
    /// Получить ожидаемый тип контента ответа
    var expectedContentType: String {
        switch self {
        case .chatCompletions:
            return "application/json"
        case .models:
            return "application/json"
        case .custom:
            return "application/json"
        }
    }
    
    /// Поддерживает ли эндпоинт SSE стриминг
    var supportsStreaming: Bool {
        switch self {
        case .chatCompletions:
            return true
        default:
            return false
        }
    }
}

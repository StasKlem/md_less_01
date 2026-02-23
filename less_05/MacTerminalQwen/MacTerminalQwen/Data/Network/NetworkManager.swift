//
//  NetworkManager.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

/// Менеджер для управления сетевыми запросами.
/// Инкапсулирует URLSession и обработку ошибок.
protocol NetworkManagerProtocol {
    /// Выполнить GET запрос
    func get(url: URL, headers: [String: String]?) async throws -> Data
    
    /// Выполнить POST запрос
    func post(url: URL, body: Data?, headers: [String: String]?) async throws -> Data
    
    /// Выполнить POST запрос с SSE стримингом
    func stream(
        url: URL,
        body: Data,
        headers: [String: String]?
    ) -> AsyncThrowingStream<String, Error>
}

/// Реализация сетевого менеджера.
final class NetworkManager: NetworkManagerProtocol {
    
    // MARK: - Properties
    
    private let session: URLSession
    private let timeout: TimeInterval
    
    // MARK: - Initialization
    
    init(
        timeout: TimeInterval = 30.0,
        configuration: URLSessionConfiguration = .ephemeral
    ) {
        self.timeout = timeout
        self.session = URLSession(configuration: configuration)
    }
    
    // MARK: - NetworkManagerProtocol
    
    func get(url: URL, headers: [String: String]? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        
        headers?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        
        return try await performRequest(request)
    }
    
    func post(url: URL, body: Data? = nil, headers: [String: String]? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.httpBody = body
        
        // Заголовки по умолчанию
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Дополнительные заголовки
        headers?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        
        return try await performRequest(request)
    }
    
    func stream(
        url: URL,
        body: Data,
        headers: [String: String]? = nil
    ) -> AsyncThrowingStream<String, Error> {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.httpBody = body
        
        // Заголовки для SSE
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        
        headers?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        
        return SSEStreamParser.createStream(from: request, timeout: timeout)
    }
    
    // MARK: - Private
    
    private func performRequest(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        
        // Проверка ответа
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.connection(NSError(domain: "Invalid response", code: -1))
        }
        
        // Проверка статуса
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NetworkError.httpStatus(httpResponse.statusCode, data)
        }
        
        return data
    }
}

// MARK: - Convenience Methods

extension NetworkManager {
    
    /// Выполнить запрос и декодировать ответ
    func get<T: Decodable>(
        url: URL,
        headers: [String: String]? = nil,
        decoder: JSONDecoder = .init()
    ) async throws -> T {
        let data = try await get(url: url, headers: headers)
        
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decoding("Failed to decode response", error)
        }
    }
    
    /// Выполнить POST запрос и декодировать ответ
    func post<T: Decodable>(
        url: URL,
        body: Data? = nil,
        headers: [String: String]? = nil,
        decoder: JSONDecoder = .init()
    ) async throws -> T {
        let data = try await post(url: url, body: body, headers: headers)
        
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decoding("Failed to decode response", error)
        }
    }
    
    /// Выполнить POST запрос с JSON-телом
    func postJSON<T: Encodable, R: Decodable>(
        url: URL,
        body: T,
        headers: [String: String]? = nil,
        encoder: JSONEncoder = .init(),
        decoder: JSONDecoder = .init()
    ) async throws -> R {
        let bodyData: Data
        do {
            bodyData = try encoder.encode(body)
        } catch {
            throw NetworkError.decoding("Failed to encode request", error)
        }
        
        return try await post(url: url, body: bodyData, headers: headers, decoder: decoder)
    }
}

// MARK: - Request Logging

extension NetworkManager {
    
    /// Логировать запрос для отладки
    private func logRequest(_ request: URLRequest) {
        logDebug("Request: \(request.httpMethod ?? "UNKNOWN") \(request.url?.absoluteString ?? "nil")")
        
        if let headers = request.allHTTPHeaderFields {
            for (key, value) in headers {
                logDebug("  Header: \(key) = \(value)")
            }
        }
        
        if let body = request.httpBody,
           let bodyString = String(data: body, encoding: .utf8) {
            logDebug("  Body: \(bodyString)")
        }
    }
    
    /// Логировать ответ для отладки
    private func logResponse(_ response: URLResponse, data: Data?) {
        if let httpResponse = response as? HTTPURLResponse {
            logDebug("Response: \(httpResponse.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))")
        }
        
        if let data = data,
           let bodyString = String(data: data, encoding: .utf8) {
            logDebug("  Body: \(bodyString.prefix(500))")
        }
    }
}

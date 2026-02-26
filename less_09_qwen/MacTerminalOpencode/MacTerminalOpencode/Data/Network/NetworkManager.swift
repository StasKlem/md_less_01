//
//  NetworkManager.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

/// Protocol for network operations
protocol NetworkManagerProtocol {
    func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T
    func performStreamingRequest(_ request: URLRequest) -> AsyncThrowingStream<Data, Error>
}

/// Manages network requests using URLSession
final class NetworkManager: NetworkManagerProtocol {
    
    private let session: URLSession
    private let timeoutInterval: TimeInterval
    
    init(timeoutInterval: TimeInterval = 60.0) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutInterval
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
        self.timeoutInterval = timeoutInterval
    }
    
    /// Performs a standard HTTP request and decodes the response
    func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        
        try validateResponse(response, data: data)
        
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AppError.parsing(.invalidJSON)
        }
    }
    
    /// Performs a streaming request returning SSE data chunks as they arrive
    func performStreamingRequest(_ request: URLRequest) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    print("[NetworkManager] Starting streaming request to: \(request.url?.absoluteString ?? "unknown")")
                    let (bytes, response) = try await self.session.bytes(for: request)
                    
                    if let httpResponse = response as? HTTPURLResponse {
                        print("[NetworkManager] Response status: \(httpResponse.statusCode)")
                        guard httpResponse.statusCode == 200 else {
                            throw AppError.network(.httpError(statusCode: httpResponse.statusCode, message: nil))
                        }
                    }
                    
                    var buffer = Data()
                    var chunkCount = 0
                    
                    for try await byte in bytes {
                        buffer.append(byte)
                        
                        if byte == UInt8(ascii: "\n") {
                            if !buffer.isEmpty {
                                chunkCount += 1
                                continuation.yield(buffer)
                                buffer.removeAll()
                            }
                        }
                    }
                    
                    if !buffer.isEmpty {
                        continuation.yield(buffer)
                    }
                    
                    print("[NetworkManager] Streaming completed, received \(chunkCount) chunks")
                    continuation.finish()
                } catch {
                    print("[NetworkManager] Streaming error: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.network(.noConnection)
        }
        
        switch httpResponse.statusCode {
        case 200..<300:
            return
        case 401:
            throw AppError.network(.unauthorized)
        case 400..<500:
            let message = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw AppError.network(.httpError(statusCode: httpResponse.statusCode, message: message?.error?.message))
        case 500..<600:
            let message = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw AppError.network(.serverError(message?.error?.message ?? "Unknown server error"))
        default:
            throw AppError.network(.httpError(statusCode: httpResponse.statusCode, message: nil))
        }
    }
}

private struct ErrorResponse: Decodable {
    let error: ErrorDetail?
}

private struct ErrorDetail: Decodable {
    let message: String?
}

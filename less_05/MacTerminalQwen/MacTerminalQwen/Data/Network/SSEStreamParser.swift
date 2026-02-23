//
//  SSEStreamParser.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

/// Парсер Server-Sent Events (SSE) для потоковых ответов.
/// Обрабатывает формат SSE согласно спецификации W3C.
final class SSEStreamParser {
    
    // MARK: - Properties
    
    private var buffer = Data()
    private let separatorData = "\n\n".data(using: .utf8)!
    
    // MARK: - Parsing
    
    /// Добавить данные и вернуть распарсенные события
    func appendData(_ data: Data) -> [SSEEvent] {
        buffer.append(data)
        return parseCompleteEvents()
    }
    
    /// Добавить строку и вернуть распарсенные события
    func appendString(_ string: String) -> [SSEEvent] {
        guard let data = string.data(using: .utf8) else {
            return []
        }
        return appendData(data)
    }
    
    /// Сбросить буфер
    func reset() {
        buffer.removeAll()
    }
    
    // MARK: - Private
    
    private func parseCompleteEvents() -> [SSEEvent] {
        var events: [SSEEvent] = []
        
        while let range = buffer.range(of: separatorData) {
            let eventData = buffer.subdata(in: 0..<range.lowerBound)
            buffer.removeSubrange(0..<range.upperBound)
            
            if let event = parseEvent(from: eventData) {
                events.append(event)
            }
        }
        
        return events
    }
    
    private func parseEvent(from data: Data) -> SSEEvent? {
        guard let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return parseEvent(from: string)
    }
    
    private func parseEvent(from string: String) -> SSEEvent? {
        var event: String?
        var eventData = ""
        var id: String?
        var retry: Int?
        
        let lines = string.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            guard !trimmed.isEmpty else { continue }
            
            if trimmed.hasPrefix("data: ") {
                let value = String(trimmed.dropFirst(6))
                if eventData.isEmpty {
                    eventData = value
                } else {
                    eventData += "\n" + value
                }
            } else if trimmed.hasPrefix("data:") {
                let value = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if eventData.isEmpty {
                    eventData = value
                } else {
                    eventData += "\n" + value
                }
            } else if trimmed.hasPrefix("event: ") {
                event = String(trimmed.dropFirst(7))
            } else if trimmed.hasPrefix("id: ") {
                id = String(trimmed.dropFirst(4))
            } else if trimmed.hasPrefix("retry: ") {
                if let retryValue = Int(String(trimmed.dropFirst(7))) {
                    retry = retryValue
                }
            }
        }
        
        guard !eventData.isEmpty else { return nil }
        
        return SSEEvent(data: eventData, event: event, id: id, retry: retry)
    }
}

// MARK: - Streaming Chunk Parser

extension SSEStreamParser {
    
    /// Парсить чанк из SSE-события
    func parseChunk(from event: SSEEvent) -> StreamingChunk? {
        StreamingChunk.fromSSEData(event.data)
    }
    
    /// Парсить контент из SSE-события
    func parseContent(from event: SSEEvent) -> String? {
        guard let chunk = parseChunk(from: event) else {
            return nil
        }
        return chunk.content
    }
}

// MARK: - Async Stream Support

extension SSEStreamParser {
    
    /// Создать AsyncThrowingStream для обработки SSE
    static func createStream(
        from urlRequest: URLRequest,
        timeout: TimeInterval = 30.0
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let session = URLSession.shared
            
            let task = session.dataTask(with: urlRequest) { data, response, error in
                if let error = error {
                    continuation.finish(throwing: error)
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    continuation.finish(throwing: NetworkError.connection(NSError(domain: "Invalid response", code: -1)))
                    return
                }
                
                guard (200..<300).contains(httpResponse.statusCode) else {
                    let statusCode = httpResponse.statusCode
                    continuation.finish(throwing: NetworkError.httpStatus(statusCode, data))
                    return
                }
                
                guard let data = data else {
                    continuation.finish(throwing: NetworkError.sseEmptyStream)
                    return
                }
                
                // Обработка не-streaming ответа
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    continuation.yield(content)
                    continuation.finish()
                    return
                }
                
                // Парсинг SSE
                Task.detached {
                    var parser = SSEStreamParser()
                    let events = parser.appendData(data)
                    
                    for event in events {
                        if event.data.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                            continuation.finish()
                            return
                        }
                        
                        if let content = parser.parseContent(from: event) {
                            continuation.yield(content)
                        }
                    }
                    
                    continuation.finish()
                }
            }
            
            task.resume()
            
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

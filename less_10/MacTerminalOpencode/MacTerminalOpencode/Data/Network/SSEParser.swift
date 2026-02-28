//
//  SSEParser.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

/// Parses Server-Sent Events (SSE) data streams
final class SSEParser: @unchecked Sendable {
    
    private var buffer: Data = Data()
    private let decoder = JSONDecoder()
    private let lock = NSLock()
    
    init() {}
    
    /// Parses incoming SSE data and returns complete chunks
    func parse(_ data: Data) -> [StreamingChunk] {
        lock.lock()
        defer { lock.unlock() }
        
        buffer.append(data)
        
        var chunks: [StreamingChunk] = []
        
        while let chunk = parseNextChunk() {
            chunks.append(chunk)
        }
        
        return chunks
    }
    
    /// Resets the parser state
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll()
    }
    
    private func parseNextChunk() -> StreamingChunk? {
        guard let dataString = String(data: buffer, encoding: .utf8) else {
            return nil
        }
        
        let lines = dataString.components(separatedBy: "\n")
        var chunkFound = false
        
        for (index, line) in lines.enumerated() {
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                
                if jsonString == "[DONE]" {
                    removeProcessedBytes(upTo: index)
                    return nil
                }
                
                if let data = jsonString.data(using: .utf8),
                   let chunk = try? decoder.decode(StreamingChunk.self, from: data) {
                    removeProcessedBytes(upTo: index)
                    return chunk
                }
                
                chunkFound = true
            } else if line.isEmpty && chunkFound {
                break
            }
        }
        
        return nil
    }
    
    private func removeProcessedBytes(upTo lineIndex: Int) {
        guard let string = String(data: buffer, encoding: .utf8) else { return }
        
        let lines = string.components(separatedBy: "\n")
        let processedLines = lines.prefix(through: lineIndex)
        let processedLength = processedLines.joined(separator: "\n").count + 1
        
        if processedLength <= buffer.count {
            buffer = buffer.dropFirst(processedLength)
        }
    }
}

extension SSEParser {
    /// Parse complete SSE response from data
    static func parseComplete(data: Data) -> [StreamingChunk] {
        guard let string = String(data: data, encoding: .utf8) else {
            return []
        }
        
        let decoder = JSONDecoder()
        var chunks: [StreamingChunk] = []
        
        for line in string.components(separatedBy: "\n") {
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                
                if jsonString == "[DONE]" {
                    continue
                }
                
                if let jsonData = jsonString.data(using: .utf8),
                   let chunk = try? decoder.decode(StreamingChunk.self, from: jsonData) {
                    chunks.append(chunk)
                }
            }
        }
        
        return chunks
    }
}

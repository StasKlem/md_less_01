//
//  StreamingChunk.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

/// Represents a single chunk from SSE streaming response
struct StreamingChunk {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [ChunkChoice]
    
    var deltaContent: String? {
        choices.first?.delta.content
    }
    
    var isFinished: Bool {
        choices.first?.finishReason != nil
    }
    
    var finishReason: String? {
        choices.first?.finishReason
    }
}

struct ChunkChoice {
    let index: Int
    let delta: ChunkDelta
    let finishReason: String?
}

struct ChunkDelta {
    let role: String?
    let content: String?
}

extension StreamingChunk: Decodable {
    enum CodingKeys: String, CodingKey {
        case id, object, created, model, choices
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        object = try container.decode(String.self, forKey: .object)
        created = try container.decode(Int.self, forKey: .created)
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        choices = try container.decode([ChunkChoice].self, forKey: .choices)
    }
}

extension ChunkChoice: Decodable {
    enum CodingKeys: String, CodingKey {
        case index, delta
        case finishReason = "finish_reason"
    }
}

extension ChunkDelta: Decodable {}

//
//  Chunk.swift
//  SupportBot
//
//  Created by Stas Klem on 02.04.2026.
//

import Foundation

/// Фрагмент документа для RAG
struct Chunk: Codable, Identifiable {
    let id: String
    let documentId: String
    let content: String
    let chunkIndex: Int
    let metadata: ChunkMetadata
    
    init(
        id: String = UUID().uuidString,
        documentId: String,
        content: String,
        chunkIndex: Int,
        metadata: ChunkMetadata = ChunkMetadata()
    ) {
        self.id = id
        self.documentId = documentId
        self.content = content
        self.chunkIndex = chunkIndex
        self.metadata = metadata
    }
}

/// Метаданные фрагмента
struct ChunkMetadata: Codable {
    let startOffset: Int
    let endOffset: Int
    let wordCount: Int
    let headings: [String]
    
    init(
        startOffset: Int = 0,
        endOffset: Int = 0,
        wordCount: Int = 0,
        headings: [String] = []
    ) {
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.wordCount = wordCount
        self.headings = headings
    }
}

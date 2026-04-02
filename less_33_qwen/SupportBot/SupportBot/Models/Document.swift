//
//  Document.swift
//  SupportBot
//
//  Created by Stas Klem on 02.04.2026.
//

import Foundation

/// Документ базы знаний
struct Document: Codable, Identifiable {
    let id: String
    let path: String
    let title: String
    let content: String
    let metadata: DocumentMetadata
    let createdAt: Date
    
    init(
        id: String = UUID().uuidString,
        path: String,
        title: String,
        content: String,
        metadata: DocumentMetadata = DocumentMetadata(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.path = path
        self.title = title
        self.content = content
        self.metadata = metadata
        self.createdAt = createdAt
    }
}

/// Метаданные документа
struct DocumentMetadata: Codable {
    let category: String
    let tags: [String]
    let lastModified: Date?
    
    init(
        category: String = "general",
        tags: [String] = [],
        lastModified: Date? = nil
    ) {
        self.category = category
        self.tags = tags
        self.lastModified = lastModified
    }
}

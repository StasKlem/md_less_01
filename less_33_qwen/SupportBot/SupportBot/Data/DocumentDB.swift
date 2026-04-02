//
//  DocumentDB.swift
//  SupportBot
//
//  Created by Stas Klem on 02.04.2026.
//

import Foundation
import SQLite
import Logging

/// База данных документов базы знаний
final class DocumentDB {
    private let logger = Logger(label: "com.supportbot.documentdb")
    private var db: Connection?
    private let dbPath: String
    
    // Таблицы
    private let documents = Table("documents")
    private let chunks = Table("chunks")
    
    // Колонки documents
    private let docId = Expression<String>("id")
    private let docPath = Expression<String>("path")
    private let docTitle = Expression<String>("title")
    private let docContent = Expression<String>("content")
    private let docCreatedAt = Expression<Date>("created_at")
    
    // Колонки chunks
    private let chunkId = Expression<String>("id")
    private let chunkDocId = Expression<String>("document_id")
    private let chunkContent = Expression<String>("content")
    private let chunkIndex = Expression<Int>("chunk_index")
    
    init(dbPath: String) {
        self.dbPath = dbPath
    }
    
    /// Инициализация базы данных
    func initialize() throws {
        logger.info("Initializing DocumentDB at: \(dbPath)")
        
        let dbDir = (dbPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dbDir, withIntermediateDirectories: true)
        
        db = try Connection(dbPath)
        try db!.run("PRAGMA journal_mode = WAL")
        
        try createDocumentsTable()
        try createChunksTable()
        
        logger.info("DocumentDB initialized successfully")
    }
    
    private func createDocumentsTable() throws {
        try db!.run(documents.create(ifNotExists: true) { t in
            t.column(docId, primaryKey: true)
            t.column(docPath)
            t.column(docTitle)
            t.column(docContent)
            t.column(docCreatedAt, defaultValue: Date())
        })
    }
    
    private func createChunksTable() throws {
        try db!.run(chunks.create(ifNotExists: true) { t in
            t.column(chunkId, primaryKey: true)
            t.column(chunkDocId)
            t.column(chunkContent)
            t.column(chunkIndex)
        })
        
        try db!.run(chunks.createIndex(chunkDocId, ifNotExists: true))
    }
    
    /// Сохранить документ
    func saveDocument(_ document: Document) throws {
        guard let db = db else { throw DBError.notInitialized }
        
        // Сначала пробуем обновить, если не существует - вставляем
        let query = documents.filter(docId == document.id)
        if (try? db.pluck(query)) != nil {
            try db.run(query.update(
                docPath <- document.path,
                docTitle <- document.title,
                docContent <- document.content,
                docCreatedAt <- document.createdAt
            ))
        } else {
            try db.run(documents.insert(
                docId <- document.id,
                docPath <- document.path,
                docTitle <- document.title,
                docContent <- document.content,
                docCreatedAt <- document.createdAt
            ))
        }
        
        logger.debug("Saved document: \(document.title)")
    }
    
    /// Сохранить чанки
    func saveChunks(_ chunks: [Chunk]) throws {
        guard let db = db else { throw DBError.notInitialized }
        
        for chunk in chunks {
            let query = self.chunks.filter(chunkId == chunk.id)
            if (try? db.pluck(query)) != nil {
                try db.run(query.update(
                    chunkDocId <- chunk.documentId,
                    chunkContent <- chunk.content,
                    chunkIndex <- chunk.chunkIndex
                ))
            } else {
                try db.run(self.chunks.insert(
                    chunkId <- chunk.id,
                    chunkDocId <- chunk.documentId,
                    chunkContent <- chunk.content,
                    chunkIndex <- chunk.chunkIndex
                ))
            }
        }
        
        logger.debug("Saved \(chunks.count) chunks")
    }
    
    /// Получить все чанки
    func getAllChunks() throws -> [Chunk] {
        guard let db = db else { throw DBError.notInitialized }
        
        return try db.prepare(chunks).map { row in
            Chunk(
                id: row[chunkId],
                documentId: row[chunkDocId],
                content: row[chunkContent],
                chunkIndex: row[chunkIndex],
                metadata: ChunkMetadata()
            )
        }
    }
    
    /// Получить чанк по ID
    func getChunk(id: String) throws -> Chunk? {
        guard let db = db else { throw DBError.notInitialized }
        
        guard let row = try db.pluck(chunks.filter(chunkId == id)) else {
            return nil
        }
        
        return Chunk(
            id: row[chunkId],
            documentId: row[chunkDocId],
            content: row[chunkContent],
            chunkIndex: row[chunkIndex],
            metadata: ChunkMetadata()
        )
    }
    
    /// Получить документ по ID
    func getDocument(id: String) throws -> Document? {
        guard let db = db else { throw DBError.notInitialized }
        
        guard let row = try db.pluck(documents.filter(docId == id)) else {
            return nil
        }
        
        return Document(
            id: row[docId],
            path: row[docPath],
            title: row[docTitle],
            content: row[docContent],
            metadata: DocumentMetadata(),
            createdAt: row[docCreatedAt]
        )
    }
    
    /// Очистить все документы
    func clearAllDocuments() throws {
        guard let db = db else { throw DBError.notInitialized }
        try db.run(documents.delete())
        try db.run(chunks.delete())
        logger.info("Cleared all documents")
    }
}

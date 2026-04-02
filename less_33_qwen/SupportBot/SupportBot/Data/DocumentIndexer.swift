//
//  DocumentIndexer.swift
//  SupportBot
//
//  Created by Stas Klem on 02.04.2026.
//

import Foundation
import Logging

/// Сервис индексации документов
final class DocumentIndexer {
    private let logger = Logger(label: "com.supportbot.indexer")
    private let documentDB: DocumentDB
    private let ragConfig: RAGConfig
    
    init(documentDB: DocumentDB, ragConfig: RAGConfig) {
        self.documentDB = documentDB
        self.ragConfig = ragConfig
    }
    
    /// Индексировать все документы из директории
    /// - Parameter directory: Путь к директории с документами
    /// - Returns: Количество проиндексированных документов
    @discardableResult
    func indexDirectory(_ directory: String) throws -> Int {
        logger.info("Starting indexing of directory: \(directory)")
        
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory) else {
            throw IndexerError.directoryNotFound(directory)
        }
        
        // Находим все .md файлы
        let enumerator = fileManager.enumerator(atPath: directory)
        var indexedCount = 0
        
        while let filePath = enumerator?.nextObject() as? String {
            guard filePath.hasSuffix(".md") else { continue }
            
            let fullPath = (directory as NSString).appendingPathComponent(filePath)
            try indexFile(fullPath, relativePath: filePath)
            indexedCount += 1
        }
        
        logger.info("Indexed \(indexedCount) documents")
        return indexedCount
    }
    
    /// Индексировать отдельный файл
    /// - Parameters:
    ///   - path: Полный путь к файлу
    ///   - relativePath: Относительный путь (для хранения)
    func indexFile(_ path: String, relativePath: String = "") throws {
        logger.debug("Indexing file: \(path)")
        
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let title = extractTitle(from: content)
        let relativePath = relativePath.isEmpty ? (path as NSString).lastPathComponent : relativePath
        
        // Создаем документ
        let category = extractCategory(from: relativePath)
        let document = Document(
            id: UUID().uuidString,
            path: relativePath,
            title: title,
            content: content,
            metadata: DocumentMetadata(category: category, tags: [], lastModified: nil),
            createdAt: Date()
        )
        
        // Сохраняем документ
        try documentDB.saveDocument(document)
        
        // Создаем чанки
        let chunks = createChunks(from: document)
        try documentDB.saveChunks(chunks)
        
        logger.debug("Indexed document '\(title)' with \(chunks.count) chunks")
    }
    
    /// Создать чанки из документа
    private func createChunks(from document: Document) -> [Chunk] {
        var chunks: [Chunk] = []
        
        // Сначала пробуем разбить по заголовкам
        let sections = document.content.splitByHeadings()
        
        if sections.count > 1 {
            // Если есть заголовки, разбиваем по секциям
            for (heading, content) in sections {
                let sectionText = "\(heading)\n\(content)"
                
                if sectionText.count > ragConfig.chunkSize {
                    // Если секция большая, разбиваем ещё
                    let subChunks = sectionText.chunked(by: ragConfig.chunkSize, overlap: ragConfig.chunkOverlap)
                    for (index, subChunk) in subChunks.enumerated() {
                        let chunk = createChunk(
                            documentId: document.id,
                            content: subChunk,
                            index: chunks.count + index,
                            heading: heading
                        )
                        chunks.append(chunk)
                    }
                } else {
                    let chunk = createChunk(
                        documentId: document.id,
                        content: sectionText,
                        index: chunks.count,
                        heading: heading
                    )
                    chunks.append(chunk)
                }
            }
        } else {
            // Если заголовков нет, разбиваем по размеру
            let textChunks = document.content.chunked(by: ragConfig.chunkSize, overlap: ragConfig.chunkOverlap)
            for (index, chunkContent) in textChunks.enumerated() {
                let chunk = createChunk(
                    documentId: document.id,
                    content: chunkContent,
                    index: index,
                    heading: document.title
                )
                chunks.append(chunk)
            }
        }
        
        return chunks
    }
    
    /// Создать чанк
    private func createChunk(
        documentId: String,
        content: String,
        index: Int,
        heading: String = ""
    ) -> Chunk {
        let headings = heading.isEmpty ? [] : [heading]
        
        return Chunk(
            id: UUID().uuidString,
            documentId: documentId,
            content: content,
            chunkIndex: index,
            metadata: ChunkMetadata(
                startOffset: 0,
                endOffset: content.count,
                wordCount: content.wordCount,
                headings: headings
            )
        )
    }
    
    /// Извлечь заголовок из Markdown файла
    private func extractTitle(from content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        
        // Ищем первый заголовок H1
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }
        
        // Если нет H1, используем первый непустой заголовок
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                // Удаляем все # и пробелы в начале
                let title = trimmed.drop(while: { $0 == "#" || $0 == " " })
                return String(title).trimmingCharacters(in: .whitespaces)
            }
        }
        
        return "Без названия"
    }
    
    /// Извлечь категорию из пути
    private func extractCategory(from path: String) -> String {
        let components = path.components(separatedBy: "/")
        
        if components.count > 1 {
            // Предпоследний компонент (директория)
            return components[components.count - 2]
        }
        
        return "general"
    }
    
    /// Переиндексировать все документы
    @discardableResult
    func reindexAll(from directory: String) throws -> Int {
        logger.info("Starting reindexing...")
        
        // Очищаем старую базу
        try documentDB.clearAllDocuments()
        
        // Индексируем заново
        return try indexDirectory(directory)
    }
}

enum IndexerError: LocalizedError {
    case directoryNotFound(String)
    case fileNotReadable(String)
    case parsingError(String)
    
    var errorDescription: String? {
        switch self {
        case .directoryNotFound(let path):
            return "Директория не найдена: \(path)"
        case .fileNotReadable(let path):
            return "Файл не читается: \(path)"
        case .parsingError(let message):
            return "Ошибка парсинга: \(message)"
        }
    }
}

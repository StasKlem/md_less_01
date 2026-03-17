import Foundation

struct FixedSizeChunker: ChunkingStrategy {
    let kind: ChunkingStrategyType = .fixed

    let chunkSize: Int
    let overlap: Int

    init(chunkSize: Int = 800, overlap: Int = 120) {
        self.chunkSize = chunkSize
        self.overlap = overlap
    }

    func makeChunks(document: ParsedDocument) throws -> [ChunkDraft] {
        guard chunkSize > 0, overlap >= 0, overlap < chunkSize else {
            throw RAGError.invalidChunkerConfiguration
        }

        let text = document.fullText
        guard !text.isEmpty else { return [] }

        var chunks: [ChunkDraft] = []
        var currentStart = text.startIndex

        while currentStart < text.endIndex {
            let remaining = text.distance(from: currentStart, to: text.endIndex)
            let length = min(chunkSize, remaining)
            let currentEnd = text.index(currentStart, offsetBy: length)

            let content = String(text[currentStart..<currentEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                let offset = text.distance(from: text.startIndex, to: currentStart)
                chunks.append(
                    ChunkDraft(
                        content: content,
                        source: document.source,
                        title: document.title,
                        section: nil,
                        offset: offset
                    )
                )
            }

            if currentEnd == text.endIndex {
                break
            }

            let backtrack = min(overlap, text.distance(from: text.startIndex, to: currentEnd))
            currentStart = text.index(currentEnd, offsetBy: -backtrack)
        }

        return chunks
    }
}

struct StructuralChunker: ChunkingStrategy {
    let kind: ChunkingStrategyType = .structural

    private let maxSectionSize: Int
    private let fallbackChunker: FixedSizeChunker

    init(maxSectionSize: Int = 1200, fallbackChunkSize: Int = 800, fallbackOverlap: Int = 120) {
        self.maxSectionSize = maxSectionSize
        self.fallbackChunker = FixedSizeChunker(chunkSize: fallbackChunkSize, overlap: fallbackOverlap)
    }

    func makeChunks(document: ParsedDocument) throws -> [ChunkDraft] {
        guard maxSectionSize > 0 else {
            throw RAGError.invalidChunkerConfiguration
        }

        if document.sections.isEmpty {
            return try fallbackChunker.makeChunks(document: document)
        }

        var chunks: [ChunkDraft] = []

        for section in document.sections {
            let trimmed = section.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.count <= maxSectionSize {
                chunks.append(
                    ChunkDraft(
                        content: trimmed,
                        source: document.source,
                        title: document.title,
                        section: section.title,
                        offset: section.offset
                    )
                )
                continue
            }

            let splitDocument = ParsedDocument(
                source: document.source,
                title: document.title,
                kind: document.kind,
                fullText: trimmed,
                sections: [ParsedSection(title: section.title, content: trimmed, offset: 0)]
            )
            let fallbackChunks = try fallbackChunker.makeChunks(document: splitDocument)
            chunks.append(contentsOf: fallbackChunks.map {
                ChunkDraft(
                    content: $0.content,
                    source: $0.source,
                    title: $0.title,
                    section: section.title,
                    offset: section.offset + $0.offset
                )
            })
        }

        return chunks
    }
}

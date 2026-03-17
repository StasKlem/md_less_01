import Foundation

enum RAGError: LocalizedError {
    case unsupportedDocumentType(URL)
    case invalidChunkerConfiguration
    case invalidEmbeddingDimension(expected: Int, actual: Int)
    case embeddingProviderUnavailable(String)
    case vectorStoreUnavailable(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedDocumentType(url):
            return "Unsupported document type: \(url.lastPathComponent)"
        case .invalidChunkerConfiguration:
            return "Invalid chunker configuration."
        case let .invalidEmbeddingDimension(expected, actual):
            return "Embedding dimension mismatch. Expected \(expected), got \(actual)."
        case let .embeddingProviderUnavailable(reason):
            return "Embedding provider is unavailable: \(reason)"
        case let .vectorStoreUnavailable(reason):
            return "Vector store is unavailable: \(reason)"
        }
    }
}

enum DocumentKind: String, Codable {
    case markdown
    case code
    case pdf
    case plainText
}

struct ParsedSection: Equatable {
    let title: String?
    let content: String
    let offset: Int
}

struct ParsedDocument: Equatable {
    let source: String
    let title: String?
    let kind: DocumentKind
    let fullText: String
    let sections: [ParsedSection]
}

struct ChunkDraft: Equatable {
    let content: String
    let source: String
    let title: String?
    let section: String?
    let offset: Int
}

struct DocumentChunk: Equatable, Identifiable {
    let id: UUID
    let content: String
    let embedding: [Float]
    let source: String
    let title: String?
    let section: String?
    let offset: Int
}

struct SearchResult: Equatable {
    let chunk: DocumentChunk
    let score: Float
}

enum ChunkingStrategyType: String, Codable, CaseIterable {
    case fixed
    case structural
}

enum RAGEmbeddingProviderKind: String, Codable {
    case appLLM
    case localONNX
}

struct RAGSettings: Codable, Equatable {
    var provider: RAGEmbeddingProviderKind
    var embeddingModel: String
    var embeddingDimension: Int
    var batchSize: Int
    var normalizeEmbeddings: Bool

    static let `default` = RAGSettings(
        provider: .appLLM,
        embeddingModel: LLMSettings.default.model.rawValue,
        embeddingDimension: 768,
        batchSize: 16,
        normalizeEmbeddings: true
    )
}

struct IndexingSummary: Equatable {
    let documentCount: Int
    let chunkCount: Int
    let indexingDurationMs: Int
}

struct ChunkingEvaluationCase: Equatable {
    let query: String
    let expectedSourceContains: String?
    let expectedSectionContains: String?
}

struct ChunkingMetrics: Equatable {
    let strategy: ChunkingStrategyType
    let chunkCount: Int
    let averageChunkLength: Double
    let medianChunkLength: Double
    let indexingDurationMs: Int
    let averageSearchLatencyMs: Int
    let recallAtK: Double
}

struct ChunkingComparisonReport: Equatable {
    let metrics: [ChunkingMetrics]
    let recommendedDefault: ChunkingStrategyType
}

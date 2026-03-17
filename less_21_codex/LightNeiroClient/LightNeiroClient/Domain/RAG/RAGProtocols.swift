import Foundation

protocol DocumentParser {
    func parse(url: URL) throws -> ParsedDocument
}

protocol ChunkingStrategy {
    var kind: ChunkingStrategyType { get }
    func makeChunks(document: ParsedDocument) throws -> [ChunkDraft]
}

protocol EmbeddingProvider {
    func embed(texts: [String], settings: RAGSettings) async throws -> [[Float]]
}

protocol VectorStore {
    func reset() async throws
    func upsert(chunks: [DocumentChunk]) async throws
    func search(queryEmbedding: [Float], topK: Int) async throws -> [SearchResult]
}

protocol RAGUseCaseFacadeProtocol {
    func index(documents: [URL], strategy: ChunkingStrategyType) async throws -> IndexingSummary
    func search(query: String, topK: Int) async throws -> [SearchResult]
    func compare(
        strategies: [ChunkingStrategyType],
        dataset: [URL],
        evaluationCases: [ChunkingEvaluationCase],
        topK: Int
    ) async throws -> ChunkingComparisonReport
}

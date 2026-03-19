import Foundation

final class IndexDocumentsUseCase {
    private let parser: DocumentParser
    private let chunkingStrategies: [ChunkingStrategyType: ChunkingStrategy]
    private let embeddingProvider: EmbeddingProvider
    private let vectorStore: VectorStore
    private let settings: RAGSettings

    init(
        parser: DocumentParser,
        chunkingStrategies: [ChunkingStrategyType: ChunkingStrategy],
        embeddingProvider: EmbeddingProvider,
        vectorStore: VectorStore,
        settings: RAGSettings
    ) {
        self.parser = parser
        self.chunkingStrategies = chunkingStrategies
        self.embeddingProvider = embeddingProvider
        self.vectorStore = vectorStore
        self.settings = settings
    }

    func execute(documents: [URL], strategy: ChunkingStrategyType) async throws -> IndexingSummary {
        let startedAt = Date()
        let chunker = try resolveChunker(for: strategy)
        // chunks: промежуточные черновики фрагментов текста после парсинга и разбиения документов.
        let chunks = try buildChunks(from: documents, using: chunker)
        // documentChunks: финальные чанки для векторного индекса (контент + метаданные + эмбеддинг).
        let documentChunks = try await buildDocumentChunks(from: chunks)

        try await vectorStore.upsert(chunks: documentChunks)

        return IndexingSummary(
            documentCount: documents.count,
            chunkCount: documentChunks.count,
            indexingDurationMs: elapsedMilliseconds(since: startedAt)
        )
    }

    private func resolveChunker(for strategy: ChunkingStrategyType) throws -> ChunkingStrategy {
        guard let chunker = chunkingStrategies[strategy] else {
            throw RAGError.invalidChunkerConfiguration
        }
        return chunker
    }

    private func buildChunks(from documents: [URL], using chunker: ChunkingStrategy) throws -> [ChunkDraft] {
        var chunks: [ChunkDraft] = []
        for url in documents {
            let parsed = try parser.parse(url: url)
            chunks.append(contentsOf: try chunker.makeChunks(document: parsed))
        }
        return chunks
    }

    private func buildDocumentChunks(from chunks: [ChunkDraft]) async throws -> [DocumentChunk] {
        // Пустой набор входных чанков не требует обращения к провайдеру эмбеддингов.
        guard !chunks.isEmpty else {
            return []
        }
        let embeddings = try await embeddingProvider.embed(texts: chunks.map(\.content), settings: settings)
        return try RAGChunkFactory.makeDocumentChunks(chunks: chunks, embeddings: embeddings)
    }
}

final class SearchChunksUseCase {
    private let embeddingProvider: EmbeddingProvider
    private let vectorStore: VectorStore
    private let settings: RAGSettings

    init(
        embeddingProvider: EmbeddingProvider,
        vectorStore: VectorStore,
        settings: RAGSettings
    ) {
        self.embeddingProvider = embeddingProvider
        self.vectorStore = vectorStore
        self.settings = settings
    }

    func execute(query: String, topK: Int) async throws -> [SearchResult] {
        try validateSearchInput(query: query, topK: topK)
        let embeddings = try await embeddingProvider.embed(texts: [query], settings: settings)
        // Для поискового запроса ожидаем ровно один эмбеддинг.
        let queryEmbedding = try RAGChunkFactory.singleEmbedding(from: embeddings)
        return try await vectorStore.search(queryEmbedding: queryEmbedding, topK: topK)
    }

    private func validateSearchInput(query: String, topK: Int) throws {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RAGError.emptyQuery
        }
        guard topK > 0 else {
            throw RAGError.invalidTopK(topK)
        }
    }
}

final class CompareChunkingStrategiesUseCase {
    private let parser: DocumentParser
    private let chunkingStrategies: [ChunkingStrategyType: ChunkingStrategy]
    private let embeddingProvider: EmbeddingProvider
    private let vectorStoreFactory: () -> VectorStore
    private let settings: RAGSettings

    init(
        parser: DocumentParser,
        chunkingStrategies: [ChunkingStrategyType: ChunkingStrategy],
        embeddingProvider: EmbeddingProvider,
        vectorStoreFactory: @escaping () -> VectorStore,
        settings: RAGSettings
    ) {
        self.parser = parser
        self.chunkingStrategies = chunkingStrategies
        self.embeddingProvider = embeddingProvider
        self.vectorStoreFactory = vectorStoreFactory
        self.settings = settings
    }

    func execute(
        strategies: [ChunkingStrategyType],
        dataset: [URL],
        evaluationCases: [ChunkingEvaluationCase],
        topK: Int
    ) async throws -> ChunkingComparisonReport {
        guard topK > 0 else {
            throw RAGError.invalidTopK(topK)
        }
        var metrics: [ChunkingMetrics] = []

        for strategy in strategies {
            let chunker = try resolveChunker(for: strategy)
            let strategyMetrics = try await evaluateStrategy(
                strategy,
                chunker: chunker,
                dataset: dataset,
                evaluationCases: evaluationCases,
                topK: topK
            )
            metrics.append(strategyMetrics)
        }

        let recommended = metrics.max(by: compareMetrics(lhs:rhs:))?.strategy ?? .structural
        return ChunkingComparisonReport(metrics: metrics, recommendedDefault: recommended)
    }

    private func resolveChunker(for strategy: ChunkingStrategyType) throws -> ChunkingStrategy {
        guard let chunker = chunkingStrategies[strategy] else {
            throw RAGError.invalidChunkerConfiguration
        }
        return chunker
    }

    private func evaluateStrategy(
        _ strategy: ChunkingStrategyType,
        chunker: ChunkingStrategy,
        dataset: [URL],
        evaluationCases: [ChunkingEvaluationCase],
        topK: Int
    ) async throws -> ChunkingMetrics {
        // Для каждой стратегии используем изолированное хранилище, чтобы метрики не влияли друг на друга.
        let store = vectorStoreFactory()
        try await store.reset()

        let startedAt = Date()
        let chunks = try buildChunks(from: dataset, using: chunker)
        let indexedChunks = try await index(chunks: chunks, into: store)
        let indexingDurationMs = elapsedMilliseconds(since: startedAt)

        let lengths = indexedChunks.map(\.content.count)
        let averageChunkLength = averageLength(lengths)
        let median = medianChunkLength(lengths)
        let evaluation = try await evaluateSearch(
            evaluationCases: evaluationCases,
            store: store,
            topK: topK
        )

        return ChunkingMetrics(
            strategy: strategy,
            chunkCount: indexedChunks.count,
            averageChunkLength: averageChunkLength,
            medianChunkLength: median,
            indexingDurationMs: indexingDurationMs,
            averageSearchLatencyMs: evaluation.averageSearchLatencyMs,
            recallAtK: evaluation.recallAtK
        )
    }

    private func buildChunks(from documents: [URL], using chunker: ChunkingStrategy) throws -> [ChunkDraft] {
        var chunks: [ChunkDraft] = []
        for url in documents {
            let parsed = try parser.parse(url: url)
            chunks.append(contentsOf: try chunker.makeChunks(document: parsed))
        }
        return chunks
    }

    private func index(chunks: [ChunkDraft], into store: VectorStore) async throws -> [DocumentChunk] {
        guard !chunks.isEmpty else {
            return []
        }
        let embeddings = try await embeddingProvider.embed(texts: chunks.map(\.content), settings: settings)
        // indexedChunks: материализованные DocumentChunk, готовые к загрузке в хранилище векторов.
        let indexedChunks = try RAGChunkFactory.makeDocumentChunks(chunks: chunks, embeddings: embeddings)
        try await store.upsert(chunks: indexedChunks)
        return indexedChunks
    }

    private func evaluateSearch(
        evaluationCases: [ChunkingEvaluationCase],
        store: VectorStore,
        topK: Int
    ) async throws -> (recallAtK: Double, averageSearchLatencyMs: Int) {
        guard !evaluationCases.isEmpty else {
            return (0, 0)
        }

        var recallHits = 0
        var totalLatencyMs = 0
        for item in evaluationCases {
            let queryStart = Date()
            let queryEmbeddings = try await embeddingProvider.embed(texts: [item.query], settings: settings)
            let queryEmbedding = try RAGChunkFactory.singleEmbedding(from: queryEmbeddings)
            let results = try await store.search(queryEmbedding: queryEmbedding, topK: topK)
            totalLatencyMs += elapsedMilliseconds(since: queryStart)

            if isQueryMatched(results: results, expected: item) {
                recallHits += 1
            }
        }

        // Recall@K считаем как долю кейсов, где в топе найден ожидаемый источник/секция.
        let recallAtK = Double(recallHits) / Double(evaluationCases.count)
        let avgSearchLatencyMs = totalLatencyMs / evaluationCases.count
        return (recallAtK, avgSearchLatencyMs)
    }

    private func averageLength(_ lengths: [Int]) -> Double {
        guard !lengths.isEmpty else {
            return 0
        }
        return Double(lengths.reduce(0, +)) / Double(lengths.count)
    }

    private func medianChunkLength(_ lengths: [Int]) -> Double {
        guard !lengths.isEmpty else { return 0 }
        let sorted = lengths.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return Double(sorted[mid - 1] + sorted[mid]) / 2.0
        }
        return Double(sorted[mid])
    }

    private func isQueryMatched(results: [SearchResult], expected: ChunkingEvaluationCase) -> Bool {
        results.contains { result in
            let sourceMatch: Bool
            if let expectedSourceContains = expected.expectedSourceContains?.lowercased(), !expectedSourceContains.isEmpty {
                sourceMatch = result.chunk.source.lowercased().contains(expectedSourceContains)
            } else {
                sourceMatch = true
            }

            let sectionMatch: Bool
            if let expectedSectionContains = expected.expectedSectionContains?.lowercased(), !expectedSectionContains.isEmpty {
                sectionMatch = (result.chunk.section ?? "").lowercased().contains(expectedSectionContains)
            } else {
                sectionMatch = true
            }

            return sourceMatch && sectionMatch
        }
    }

    private func compareMetrics(lhs: ChunkingMetrics, rhs: ChunkingMetrics) -> Bool {
        if lhs.recallAtK != rhs.recallAtK {
            return lhs.recallAtK < rhs.recallAtK
        }
        if lhs.averageSearchLatencyMs != rhs.averageSearchLatencyMs {
            return lhs.averageSearchLatencyMs > rhs.averageSearchLatencyMs
        }
        return lhs.chunkCount > rhs.chunkCount
    }
}

final class ResetRAGIndexUseCase {
    private let vectorStore: VectorStore

    init(vectorStore: VectorStore) {
        self.vectorStore = vectorStore
    }

    func execute() async throws {
        try await vectorStore.reset()
    }
}

private enum RAGChunkFactory {
    static func makeDocumentChunks(chunks: [ChunkDraft], embeddings: [[Float]]) throws -> [DocumentChunk] {
        // Жестко валидируем соответствие размеров, чтобы избежать тихой потери чанков при zip.
        guard chunks.count == embeddings.count else {
            throw RAGError.invalidEmbeddingDimension(expected: chunks.count, actual: embeddings.count)
        }

        return zip(chunks, embeddings).map { chunk, embedding in
            DocumentChunk(
                id: UUID(),
                content: chunk.content,
                embedding: embedding,
                source: chunk.source,
                title: chunk.title,
                section: chunk.section,
                offset: chunk.offset
            )
        }
    }

    static func singleEmbedding(from embeddings: [[Float]]) throws -> [Float] {
        // Для сценария единичного запроса любое отклонение — это ошибка контракта провайдера.
        guard embeddings.count == 1, let embedding = embeddings.first else {
            throw RAGError.invalidEmbeddingDimension(expected: 1, actual: embeddings.count)
        }
        return embedding
    }
}

private func elapsedMilliseconds(since startDate: Date) -> Int {
    Int(Date().timeIntervalSince(startDate) * 1000.0)
}

final class RAGUseCaseFacade: RAGUseCaseFacadeProtocol {
    private let indexUseCase: IndexDocumentsUseCase
    private let searchUseCase: SearchChunksUseCase
    private let compareUseCase: CompareChunkingStrategiesUseCase
    private let resetUseCase: ResetRAGIndexUseCase

    init(
        indexUseCase: IndexDocumentsUseCase,
        searchUseCase: SearchChunksUseCase,
        compareUseCase: CompareChunkingStrategiesUseCase,
        resetUseCase: ResetRAGIndexUseCase
    ) {
        self.indexUseCase = indexUseCase
        self.searchUseCase = searchUseCase
        self.compareUseCase = compareUseCase
        self.resetUseCase = resetUseCase
    }

    func index(documents: [URL], strategy: ChunkingStrategyType) async throws -> IndexingSummary {
        try await indexUseCase.execute(documents: documents, strategy: strategy)
    }

    func search(query: String, topK: Int) async throws -> [SearchResult] {
        try await searchUseCase.execute(query: query, topK: topK)
    }

    func compare(
        strategies: [ChunkingStrategyType],
        dataset: [URL],
        evaluationCases: [ChunkingEvaluationCase],
        topK: Int
    ) async throws -> ChunkingComparisonReport {
        try await compareUseCase.execute(
            strategies: strategies,
            dataset: dataset,
            evaluationCases: evaluationCases,
            topK: topK
        )
    }

    func resetIndex() async throws {
        try await resetUseCase.execute()
    }
}

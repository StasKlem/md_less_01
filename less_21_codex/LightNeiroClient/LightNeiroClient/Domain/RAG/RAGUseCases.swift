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
        guard let chunker = chunkingStrategies[strategy] else {
            throw RAGError.invalidChunkerConfiguration
        }

        var chunks: [ChunkDraft] = []
        for url in documents {
            let parsed = try parser.parse(url: url)
            let builtChunks = try chunker.makeChunks(document: parsed)
            chunks.append(contentsOf: builtChunks)
        }

        let embeddings = try await embeddingProvider.embed(texts: chunks.map(\.content), settings: settings)
        let documentChunks = try zipChunksWithEmbeddings(chunks: chunks, embeddings: embeddings)

        try await vectorStore.upsert(chunks: documentChunks)

        return IndexingSummary(
            documentCount: documents.count,
            chunkCount: documentChunks.count,
            indexingDurationMs: Int(Date().timeIntervalSince(startedAt) * 1000.0)
        )
    }

    private func zipChunksWithEmbeddings(chunks: [ChunkDraft], embeddings: [[Float]]) throws -> [DocumentChunk] {
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
        let embeddings = try await embeddingProvider.embed(texts: [query], settings: settings)
        guard let queryEmbedding = embeddings.first else {
            return []
        }
        return try await vectorStore.search(queryEmbedding: queryEmbedding, topK: topK)
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
        var metrics: [ChunkingMetrics] = []

        for strategy in strategies {
            guard let chunker = chunkingStrategies[strategy] else { continue }
            let store = vectorStoreFactory()
            try await store.reset()

            let startedAt = Date()
            var allChunks: [ChunkDraft] = []
            for url in dataset {
                let parsed = try parser.parse(url: url)
                allChunks.append(contentsOf: try chunker.makeChunks(document: parsed))
            }

            let embeddings = try await embeddingProvider.embed(texts: allChunks.map(\.content), settings: settings)
            let indexedChunks = zip(allChunks, embeddings).map { chunk, embedding in
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
            try await store.upsert(chunks: indexedChunks)
            let indexingDurationMs = Int(Date().timeIntervalSince(startedAt) * 1000.0)

            let lengths = indexedChunks.map { $0.content.count }
            let average = lengths.isEmpty ? 0 : Double(lengths.reduce(0, +)) / Double(lengths.count)
            let median = medianChunkLength(lengths)

            var recallHits = 0
            var totalLatencyMs = 0
            for item in evaluationCases {
                let queryStart = Date()
                let queryEmbedding = try await embeddingProvider.embed(texts: [item.query], settings: settings).first ?? []
                let results = try await store.search(queryEmbedding: queryEmbedding, topK: topK)
                totalLatencyMs += Int(Date().timeIntervalSince(queryStart) * 1000.0)

                if isQueryMatched(results: results, expected: item) {
                    recallHits += 1
                }
            }

            let recallAtK: Double
            if evaluationCases.isEmpty {
                recallAtK = 0
            } else {
                recallAtK = Double(recallHits) / Double(evaluationCases.count)
            }

            let avgSearchLatencyMs: Int
            if evaluationCases.isEmpty {
                avgSearchLatencyMs = 0
            } else {
                avgSearchLatencyMs = totalLatencyMs / evaluationCases.count
            }

            metrics.append(
                ChunkingMetrics(
                    strategy: strategy,
                    chunkCount: indexedChunks.count,
                    averageChunkLength: average,
                    medianChunkLength: median,
                    indexingDurationMs: indexingDurationMs,
                    averageSearchLatencyMs: avgSearchLatencyMs,
                    recallAtK: recallAtK
                )
            )
        }

        let recommended = metrics.max(by: compareMetrics(lhs:rhs:))?.strategy ?? .structural
        return ChunkingComparisonReport(metrics: metrics, recommendedDefault: recommended)
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

final class RAGUseCaseFacade: RAGUseCaseFacadeProtocol {
    private let indexUseCase: IndexDocumentsUseCase
    private let searchUseCase: SearchChunksUseCase
    private let compareUseCase: CompareChunkingStrategiesUseCase

    init(
        indexUseCase: IndexDocumentsUseCase,
        searchUseCase: SearchChunksUseCase,
        compareUseCase: CompareChunkingStrategiesUseCase
    ) {
        self.indexUseCase = indexUseCase
        self.searchUseCase = searchUseCase
        self.compareUseCase = compareUseCase
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
}

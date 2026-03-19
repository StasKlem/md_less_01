import Foundation

enum RAGModuleFactory {
    static let defaultDocumentRelativePaths: [String] = [
//        "README.md",
//        "LightNeiroClient/LightNeiroClient/Doc/mobile_system_design_guide.md"
        "LightNeiroClient/LightNeiroClient/Doc/ai.md"
    ]

    static func defaultDocumentURLs(baseDirectory: URL) -> [URL] {
        defaultDocumentRelativePaths
            .map { baseDirectory.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func makeFacade(
        settings: RAGSettings = .default,
        vectorStore: VectorStore? = nil,
        embeddingProvider: EmbeddingProvider? = nil
    ) -> RAGUseCaseFacadeProtocol {
        let parser = CompositeDocumentParser()
        let fixedChunker = FixedSizeChunker()
        let structuralChunker = StructuralChunker()
        let chunkers: [ChunkingStrategyType: ChunkingStrategy] = [
            .fixed: fixedChunker,
            .structural: structuralChunker
        ]

        let resolvedEmbeddingProvider: EmbeddingProvider
        if let embeddingProvider {
            resolvedEmbeddingProvider = embeddingProvider
        } else {
            switch settings.provider {
            case .appLLM:
                resolvedEmbeddingProvider = AppLLMEmbeddingProvider()
            case .localONNX:
                resolvedEmbeddingProvider = LocalONNXEmbeddingProvider()
            }
        }

        let resolvedVectorStore = vectorStore ?? SQLiteVSSVectorStore(embeddingDimension: settings.embeddingDimension)

        let indexUseCase = IndexDocumentsUseCase(
            parser: parser,
            chunkingStrategies: chunkers,
            embeddingProvider: resolvedEmbeddingProvider,
            vectorStore: resolvedVectorStore,
            settings: settings
        )
        let searchUseCase = SearchChunksUseCase(
            embeddingProvider: resolvedEmbeddingProvider,
            vectorStore: resolvedVectorStore,
            settings: settings
        )
        let compareUseCase = CompareChunkingStrategiesUseCase(
            parser: parser,
            chunkingStrategies: chunkers,
            embeddingProvider: resolvedEmbeddingProvider,
            vectorStoreFactory: { InMemoryVectorStore() },
            settings: settings
        )
        let resetUseCase = ResetRAGIndexUseCase(vectorStore: resolvedVectorStore)

        return RAGUseCaseFacade(
            indexUseCase: indexUseCase,
            searchUseCase: searchUseCase,
            compareUseCase: compareUseCase,
            resetUseCase: resetUseCase
        )
    }
}

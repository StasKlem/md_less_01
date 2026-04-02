import Foundation

enum RAGModuleFactory {
    static func defaultDocumentURLs(baseDirectory: URL) -> [URL] {
        var collected: [URL] = []

        if let readmeURL = existingURL(baseDirectory.appendingPathComponent("README.md")) {
            collected.append(readmeURL)
        }

        let documentationFolders = [
            baseDirectory.appendingPathComponent("docs", isDirectory: true),
            baseDirectory.appendingPathComponent("LightNeiroClient/Doc", isDirectory: true)
        ]

        for folder in documentationFolders {
            collected.append(contentsOf: markdownFiles(in: folder))
        }

        var unique: [URL] = []
        var seen = Set<String>()
        for url in collected {
            let path = url.standardizedFileURL.path
            guard !seen.contains(path) else { continue }
            seen.insert(path)
            unique.append(url)
        }
        return unique
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

    private static func existingURL(_ url: URL) -> URL? {
        FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func markdownFiles(in directory: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            guard ext == "md" || ext == "markdown" else { continue }
            files.append(fileURL)
        }

        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}

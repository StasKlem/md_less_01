import Foundation

protocol SendMessageRAGCoordinating {
    /// Возвращает итоговый system prompt с учетом RAG-контракта.
    func makeSystemPrompt(extraInstruction: String?, ragDecision: SendMessageRAGDecision) -> String

    /// Определяет стратегию ответа в RAG-сценарии.
    func buildDecision(settings: LLMSettings, userText: String) async -> SendMessageRAGDecision
}

enum SendMessageRAGCoordinatorFactory {
    /// Создает координатор RAG-ветки отправки сообщения.
    static func make(
        ragUseCaseFacade: RAGUseCaseFacadeProtocol?,
        ragDocumentsProvider: @escaping @Sendable () -> [URL],
        initialIndexedRAGStrategy: ChunkingStrategyType?
    ) -> SendMessageRAGCoordinating {
        SendMessageRAGCoordinator(
            ragUseCaseFacade: ragUseCaseFacade,
            ragDocumentsProvider: ragDocumentsProvider,
            initialIndexedRAGStrategy: initialIndexedRAGStrategy
        )
    }
}

enum SendMessageRAGDecision {
    case answerWithEvidence(retrieval: [SearchResult])
    case needsClarification
    case disabledOrUnavailable
}

fileprivate final class SendMessageRAGCoordinator: SendMessageRAGCoordinating {
    private let ragUseCaseFacade: RAGUseCaseFacadeProtocol?
    private let ragDocumentsProvider: @Sendable () -> [URL]
    private let ragIndexState: RAGIndexState

    init(
        ragUseCaseFacade: RAGUseCaseFacadeProtocol?,
        ragDocumentsProvider: @escaping @Sendable () -> [URL],
        initialIndexedRAGStrategy: ChunkingStrategyType?
    ) {
        self.ragUseCaseFacade = ragUseCaseFacade
        self.ragDocumentsProvider = ragDocumentsProvider
        self.ragIndexState = RAGIndexState(initialStrategy: initialIndexedRAGStrategy)
    }

    func makeSystemPrompt(extraInstruction: String?, ragDecision: SendMessageRAGDecision) -> String {
        let base = "You are a helpful assistant."
        var blocks: [String] = [base]

        if let extraInstruction {
            let trimmed = extraInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                blocks.append(trimmed)
            }
        }

        if case .answerWithEvidence(let retrieval) = ragDecision {
            blocks.append(ragJSONContractBlock())
            blocks.append(formatRAGEvidenceBlock(retrieval))
        }

        return blocks.joined(separator: "\n\n")
    }

    func buildDecision(settings: LLMSettings, userText: String) async -> SendMessageRAGDecision {
        guard settings.isRAGEnabled, let ragUseCaseFacade else { return .disabledOrUnavailable }

        do {
            try await ensureRAGIndexIsReady(ragUseCaseFacade, strategy: settings.ragChunkingStrategy)
            let normalizedThreshold = normalizedRAGThreshold(settings.ragRelevanceThreshold)

            if settings.isRAGPostFilteringEnabled {
                let topKBeforeFiltering = max(1, settings.ragTopKBeforeFiltering)
                let topKAfterFiltering = max(1, settings.ragTopKAfterFiltering)
                let results = try await ragUseCaseFacade.search(query: userText, topK: topKBeforeFiltering)
                let maxScore = Double(results.map(\.score).max() ?? 0)
                let filtered = results.filter { Double($0.score) >= normalizedThreshold }
                let finalResults = Array(filtered.prefix(topKAfterFiltering))

                logRAGPostFilteringStats(
                    total: results.count,
                    afterThreshold: filtered.count,
                    finalCount: finalResults.count,
                    threshold: normalizedThreshold,
                    topKBeforeFiltering: topKBeforeFiltering,
                    topKAfterFiltering: topKAfterFiltering
                )
                guard !finalResults.isEmpty, maxScore >= normalizedThreshold else {
                    return .needsClarification
                }
                return .answerWithEvidence(retrieval: finalResults)
            }

            let legacyResults = try await ragUseCaseFacade.search(query: userText, topK: 4)
            let maxScore = Double(legacyResults.map(\.score).max() ?? 0)
            guard !legacyResults.isEmpty, maxScore >= normalizedThreshold else {
                return .needsClarification
            }
            return .answerWithEvidence(retrieval: legacyResults)
        } catch {
#if DEBUG
            print("[RAG] Контекст не собран: \(error)")
#endif
            return .disabledOrUnavailable
        }
    }

    private func normalizedRAGThreshold(_ threshold: Double) -> Double {
        min(1.0, max(0.0, threshold))
    }

    private func logRAGPostFilteringStats(
        total: Int,
        afterThreshold: Int,
        finalCount: Int,
        threshold: Double,
        topKBeforeFiltering: Int,
        topKAfterFiltering: Int
    ) {
        let removedByThreshold = max(0, total - afterThreshold)
        let removedByTopK = max(0, afterThreshold - finalCount)
        let totalRemoved = max(0, total - finalCount)
        print(
            "[RAG] Пост-фильтрация: total=\(total), threshold>=\(String(format: "%.2f", threshold)), " +
            "afterThreshold=\(afterThreshold), final=\(finalCount), removedByThreshold=\(removedByThreshold), " +
            "removedByTopK=\(removedByTopK), totalFilteredOut=\(totalRemoved), " +
            "topKBefore=\(topKBeforeFiltering), topKAfter=\(topKAfterFiltering)"
        )
    }

    private func ensureRAGIndexIsReady(
        _ ragUseCaseFacade: RAGUseCaseFacadeProtocol,
        strategy: ChunkingStrategyType
    ) async throws {
        if await ragIndexState.isReady(for: strategy) {
            return
        }

        let documents = ragDocumentsProvider()
        guard !documents.isEmpty else {
            return
        }

        _ = try await ragUseCaseFacade.index(documents: documents, strategy: strategy)
        await ragIndexState.markReady(for: strategy)
    }

    private func formatRAGEvidenceBlock(_ results: [SearchResult]) -> String {
        var lines: [String] = ["RAG_EVIDENCE:"]

        for (index, result) in results.enumerated() {
            let source = result.chunk.source
            let section = result.chunk.section ?? "null"
            let text = result.chunk.content
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("[\(index + 1)] chunk_id=\(result.chunk.id.uuidString) source=\(source) section=\(section) text=\(text)")
        }
        return lines.joined(separator: "\n")
    }

    private func ragJSONContractBlock() -> String {
        """
        Верни ТОЛЬКО валидный JSON без markdown и без пояснений.
        Схема JSON:
        {
          "answer": "string",
          "sources": [
            { "source": "string", "section": "string|null", "chunk_id": "string" }
          ],
          "quotes": [
            { "chunk_id": "string", "source": "string", "section": "string|null", "text": "string" }
          ]
        }
        Правила:
        - Используй только фрагменты из блока RAG_EVIDENCE.
        - Для каждого элемента quotes chunk_id обязан существовать в sources.
        - Для ответа по данным RAG массивы sources и quotes должны быть непустыми.
        - Не добавляй дополнительные поля.
        """
    }
}

fileprivate actor RAGIndexState {
    private var indexedStrategy: ChunkingStrategyType?

    init(initialStrategy: ChunkingStrategyType? = nil) {
        indexedStrategy = initialStrategy
    }

    func isReady(for strategy: ChunkingStrategyType) -> Bool {
        indexedStrategy == strategy
    }

    func markReady(for strategy: ChunkingStrategyType) {
        indexedStrategy = strategy
    }
}

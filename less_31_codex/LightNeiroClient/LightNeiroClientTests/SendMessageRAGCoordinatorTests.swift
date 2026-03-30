import XCTest
@testable import LightNeiroClient

final class SendMessageRAGCoordinatorTests: XCTestCase {
    func testBuildDecisionUsesConfiguredTopKWhenPostFilteringEnabled() async throws {
        let ragSpy = RAGFacadeCoordinatorSpy(
            searchResults: [
                Self.makeSearchResult(content: "релевантный", score: 0.91),
                Self.makeSearchResult(content: "шум", score: 0.30)
            ]
        )
        let coordinator = SendMessageRAGCoordinatorFactory.make(
            ragUseCaseFacade: ragSpy,
            ragDocumentsProvider: { [] },
            initialIndexedRAGStrategy: .structural
        )

        var settings = LLMSettings.default
        settings.isRAGEnabled = true
        settings.isRAGPostFilteringEnabled = true
        settings.ragTopKBeforeFiltering = 7
        settings.ragTopKAfterFiltering = 1
        settings.ragRelevanceThreshold = 0.80

        let decision = await coordinator.buildDecision(settings: settings, userText: "Запрос")

        let topK = await ragSpy.lastSearchTopK
        XCTAssertEqual(topK, 7)
        switch decision {
        case .answerWithEvidence(let retrieval):
            XCTAssertEqual(retrieval.count, 1)
            XCTAssertEqual(retrieval.first?.chunk.content, "релевантный")
        default:
            XCTFail("Ожидалось решение answerWithEvidence")
        }
    }

    func testBuildDecisionUsesLegacyTopKWhenPostFilteringDisabled() async {
        let ragSpy = RAGFacadeCoordinatorSpy(
            searchResults: [Self.makeSearchResult(content: "legacy", score: 0.91)]
        )
        let coordinator = SendMessageRAGCoordinatorFactory.make(
            ragUseCaseFacade: ragSpy,
            ragDocumentsProvider: { [] },
            initialIndexedRAGStrategy: .structural
        )

        var settings = LLMSettings.default
        settings.isRAGEnabled = true
        settings.isRAGPostFilteringEnabled = false
        settings.ragTopKBeforeFiltering = 12

        _ = await coordinator.buildDecision(settings: settings, userText: "legacy")

        let topK = await ragSpy.lastSearchTopK
        XCTAssertEqual(topK, 4)
    }

    func testBuildDecisionFallsBackToLLMWhenScoresBelowThreshold() async {
        let ragSpy = RAGFacadeCoordinatorSpy(
            searchResults: [Self.makeSearchResult(content: "низкая релевантность", score: 0.2)]
        )
        let coordinator = SendMessageRAGCoordinatorFactory.make(
            ragUseCaseFacade: ragSpy,
            ragDocumentsProvider: { [] },
            initialIndexedRAGStrategy: .structural
        )

        var settings = LLMSettings.default
        settings.isRAGEnabled = true
        settings.isRAGPostFilteringEnabled = true
        settings.ragRelevanceThreshold = 0.95

        let decision = await coordinator.buildDecision(settings: settings, userText: "Запрос")

        if case .fallbackToLLM = decision {
            XCTAssertTrue(true)
        } else {
            XCTFail("Ожидалось решение fallbackToLLM")
        }
    }

    func testBuildDecisionReturnsDisabledWhenRAGIsOff() async {
        let ragSpy = RAGFacadeCoordinatorSpy(searchResults: [])
        let coordinator = SendMessageRAGCoordinatorFactory.make(
            ragUseCaseFacade: ragSpy,
            ragDocumentsProvider: { [] },
            initialIndexedRAGStrategy: nil
        )

        var settings = LLMSettings.default
        settings.isRAGEnabled = false

        let decision = await coordinator.buildDecision(settings: settings, userText: "Запрос")

        if case .disabledOrUnavailable = decision {
            XCTAssertTrue(true)
        } else {
            XCTFail("Ожидалось решение disabledOrUnavailable")
        }
        let searchCalls = await ragSpy.searchCallCount
        XCTAssertEqual(searchCalls, 0)
    }

    private static func makeSearchResult(content: String, score: Float) -> SearchResult {
        let chunk = DocumentChunk(
            id: UUID(),
            content: content,
            embedding: [0, 1, 0],
            source: "/tmp/rag.md",
            title: "rag",
            section: "intro",
            offset: 0
        )
        return SearchResult(chunk: chunk, score: score)
    }
}

private actor RAGFacadeCoordinatorSpy: RAGUseCaseFacadeProtocol {
    private let searchResults: [SearchResult]
    private(set) var lastSearchTopK: Int?
    private(set) var searchCallCount = 0

    init(searchResults: [SearchResult]) {
        self.searchResults = searchResults
    }

    func index(documents: [URL], strategy: ChunkingStrategyType) async throws -> IndexingSummary {
        _ = documents
        _ = strategy
        return IndexingSummary(documentCount: 0, chunkCount: 0, indexingDurationMs: 0)
    }

    func search(query: String, topK: Int) async throws -> [SearchResult] {
        _ = query
        searchCallCount += 1
        lastSearchTopK = topK
        return searchResults
    }

    func compare(
        strategies: [ChunkingStrategyType],
        dataset: [URL],
        evaluationCases: [ChunkingEvaluationCase],
        topK: Int
    ) async throws -> ChunkingComparisonReport {
        _ = strategies
        _ = dataset
        _ = evaluationCases
        _ = topK
        return ChunkingComparisonReport(metrics: [], recommendedDefault: .structural)
    }

    func resetIndex() async throws {}
}

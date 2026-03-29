import XCTest
@testable import LightNeiroClient

final class ResetRAGEmbeddingsUseCaseTests: XCTestCase {
    func testExecuteResetsRAGIndexAndClearsReadinessFlags() async throws {
        let ragFacade = RAGFacadeResetSpy()
        let readinessRepository = RAGIndexReadinessRepositorySpy()
        let useCase = ResetRAGEmbeddingsUseCase(
            ragUseCaseFacade: ragFacade,
            ragIndexReadinessRepository: readinessRepository
        )

        try await useCase.execute()

        let resetCalls = await ragFacade.resetCallCount
        XCTAssertEqual(resetCalls, 1)
        XCTAssertEqual(readinessRepository.clearAllCallCount, 1)
    }
}

private actor RAGFacadeResetSpy: RAGUseCaseFacadeProtocol {
    private(set) var resetCallCount = 0

    func index(documents: [URL], strategy: ChunkingStrategyType) async throws -> IndexingSummary {
        _ = documents
        _ = strategy
        return IndexingSummary(documentCount: 0, chunkCount: 0, indexingDurationMs: 0)
    }

    func search(query: String, topK: Int) async throws -> [SearchResult] {
        _ = query
        _ = topK
        return []
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

    func resetIndex() async throws {
        resetCallCount += 1
    }
}

private final class RAGIndexReadinessRepositorySpy: RAGIndexReadinessRepositoryProtocol {
    private(set) var clearAllCallCount = 0

    func isReady(for strategy: ChunkingStrategyType) -> Bool {
        _ = strategy
        return false
    }

    func markReady(for strategy: ChunkingStrategyType) {
        _ = strategy
    }

    func clearAll() {
        clearAllCallCount += 1
    }
}

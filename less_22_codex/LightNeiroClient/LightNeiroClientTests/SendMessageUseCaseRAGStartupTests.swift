import XCTest
@testable import LightNeiroClient

final class SendMessageUseCaseRAGStartupTests: XCTestCase {
    func testExecuteSkipsReindexWhenStartupStrategyAlreadyIndexed() async throws {
        let settingsRepository = MockSettingsRepository()
        let messageRepository = MockMessageRepository()
        let shortTermRepository = MockShortTermMemoryRepository()
        let workingMemoryRepository = MockWorkingMemoryRepository()
        let longTermMemoryRepository = MockLongTermMemoryRepository()
        let metricsRepository = MockMetricsRepository()
        let llmClient = MockLLMClient()
        let ragSpy = RAGFacadeSpy()

        let buildMemoryContext = BuildMemoryContextUseCase(
            shortTermRepository: shortTermRepository,
            workingMemoryRepository: workingMemoryRepository,
            longTermMemoryRepository: longTermMemoryRepository,
            messageRepository: messageRepository
        )
        let updateShortTermMemory = UpdateShortTermMemoryUseCase(
            messageRepository: messageRepository,
            shortTermRepository: shortTermRepository
        )
        let updateWorkingMemory = UpdateWorkingMemoryUseCase(
            workingMemoryRepository: workingMemoryRepository
        )
        let updateLongTermMemory = UpdateLongTermMemoryUseCase(
            longTermRepository: longTermMemoryRepository,
            messageRepository: messageRepository,
            llmClient: llmClient,
            legacyFactsRepository: MockFactsRepository()
        )
        let useCase = SendMessageUseCase(
            settingsRepository: settingsRepository,
            messageRepository: messageRepository,
            llmClient: llmClient,
            buildMemoryContextUseCase: buildMemoryContext,
            updateShortTermMemoryUseCase: updateShortTermMemory,
            updateWorkingMemoryUseCase: updateWorkingMemory,
            updateLongTermMemoryUseCase: updateLongTermMemory,
            metricsRepository: metricsRepository,
            ragUseCaseFacade: ragSpy,
            ragDocumentsProvider: {
                [URL(fileURLWithPath: "/tmp/rag.md")]
            },
            initialIndexedRAGStrategy: .structural
        )

        let sessionID = UUID()
        let branchID = UUID()
        var settings = LLMSettings.default
        settings.isRAGEnabled = true
        settings.isMemoryEnabled = false
        settings.ragChunkingStrategy = .structural
        try await settingsRepository.saveSettings(sessionID: sessionID, settings: settings)

        _ = try await useCase.execute(
            sessionID: sessionID,
            branchID: branchID,
            userText: "Где хранится индекс?",
            assistantInstruction: nil
        )

        let indexCalls = await ragSpy.indexCallCount
        let searchCalls = await ragSpy.searchCallCount
        XCTAssertEqual(indexCalls, 0)
        XCTAssertEqual(searchCalls, 1)
    }
}

private actor RAGFacadeSpy: RAGUseCaseFacadeProtocol {
    private(set) var indexCallCount = 0
    private(set) var searchCallCount = 0

    func index(documents: [URL], strategy: ChunkingStrategyType) async throws -> IndexingSummary {
        _ = documents
        _ = strategy
        indexCallCount += 1
        return IndexingSummary(documentCount: 0, chunkCount: 0, indexingDurationMs: 0)
    }

    func search(query: String, topK: Int) async throws -> [SearchResult] {
        _ = query
        _ = topK
        searchCallCount += 1
        let chunk = DocumentChunk(
            id: UUID(),
            content: "stub context",
            embedding: [0, 1, 0],
            source: "/tmp/rag.md",
            title: "rag",
            section: "intro",
            offset: 0
        )
        return [SearchResult(chunk: chunk, score: 0.9)]
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
}

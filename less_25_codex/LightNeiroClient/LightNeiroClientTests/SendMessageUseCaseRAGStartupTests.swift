import XCTest
@testable import LightNeiroClient

@MainActor
final class SendMessageUseCaseRAGStartupTests: XCTestCase {
    func testExecuteSkipsReindexWhenStartupStrategyAlreadyIndexed() async throws {
        let llmClient = LLMClientSpy()
        let ragSpy = RAGFacadeSpy(
            searchResults: [Self.makeSearchResult(content: "stub context", score: 0.9)]
        )
        let sut = makeUseCase(llmClient: llmClient, ragSpy: ragSpy)

                var settings = LLMSettings.default
        settings.isRAGEnabled = true
        settings.isMemoryEnabled = false
        settings.ragChunkingStrategy = .structural
        try await sut.settingsRepository.saveSettings(settings: settings)

        _ = try await sut.useCase.execute(
            userText: "Где хранится индекс?",
            assistantInstruction: nil
        )

        let indexCalls = await ragSpy.indexCallCount
        let searchCalls = await ragSpy.searchCallCount
        XCTAssertEqual(indexCalls, 0)
        XCTAssertEqual(searchCalls, 1)
    }

    func testExecuteAppliesPostFilteringAndConfiguredTopKWhenEnabled() async throws {
        let llmClient = LLMClientSpy()
        let ragSpy = RAGFacadeSpy(
            searchResults: [
                Self.makeSearchResult(content: "релевантный-1", score: 0.92),
                Self.makeSearchResult(content: "шум", score: 0.35),
                Self.makeSearchResult(content: "релевантный-2", score: 0.88)
            ]
        )
        let sut = makeUseCase(llmClient: llmClient, ragSpy: ragSpy)

                var settings = LLMSettings.default
        settings.isRAGEnabled = true
        settings.isMemoryEnabled = false
        settings.ragChunkingStrategy = .structural
        settings.isRAGPostFilteringEnabled = true
        settings.ragTopKBeforeFiltering = 6
        settings.ragTopKAfterFiltering = 1
        settings.ragRelevanceThreshold = 0.80
        try await sut.settingsRepository.saveSettings(settings: settings)

        _ = try await sut.useCase.execute(
            userText: "Найди контекст",
            assistantInstruction: nil
        )

        let lastSearchTopK = await ragSpy.lastSearchTopK
        XCTAssertEqual(lastSearchTopK, 6)

        let capturedRequest = await llmClient.capturedRequest()
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertTrue(request.systemPrompt.contains("Верни ТОЛЬКО валидный JSON"))
        XCTAssertTrue(request.systemPrompt.contains("chunk_id="))
        XCTAssertTrue(request.systemPrompt.contains("релевантный-1"))
        XCTAssertFalse(request.systemPrompt.contains("шум"))
        XCTAssertFalse(request.systemPrompt.contains("релевантный-2"))
    }

    func testExecuteUsesLegacyTopKWhenPostFilteringDisabled() async throws {
        let llmClient = LLMClientSpy()
        let ragSpy = RAGFacadeSpy(
            searchResults: [Self.makeSearchResult(content: "legacy", score: 0.20)]
        )
        let sut = makeUseCase(llmClient: llmClient, ragSpy: ragSpy)

                var settings = LLMSettings.default
        settings.isRAGEnabled = true
        settings.isMemoryEnabled = false
        settings.ragChunkingStrategy = .structural
        settings.isRAGPostFilteringEnabled = false
        settings.ragTopKBeforeFiltering = 12
        settings.ragTopKAfterFiltering = 2
        settings.ragRelevanceThreshold = 0.99
        try await sut.settingsRepository.saveSettings(settings: settings)

        _ = try await sut.useCase.execute(
            userText: "Покажи legacy режим",
            assistantInstruction: nil
        )

        let lastSearchTopK = await ragSpy.lastSearchTopK
        XCTAssertEqual(lastSearchTopK, 4)
    }

    func testExecuteReturnsNeedsClarificationJSONAndSkipsLLMWhenRelevanceBelowThreshold() async throws {
        let llmClient = LLMClientSpy()
        let ragSpy = RAGFacadeSpy(
            searchResults: [Self.makeSearchResult(content: "слабое совпадение", score: 0.21)]
        )
        let sut = makeUseCase(llmClient: llmClient, ragSpy: ragSpy)

                var settings = LLMSettings.default
        settings.isRAGEnabled = true
        settings.isMemoryEnabled = false
        settings.isRAGPostFilteringEnabled = true
        settings.ragTopKBeforeFiltering = 5
        settings.ragTopKAfterFiltering = 3
        settings.ragRelevanceThreshold = 0.95
        try await sut.settingsRepository.saveSettings(settings: settings)

        let assistant = try await sut.useCase.execute(
            userText: "Сформулируй ответ",
            assistantInstruction: nil
        )

        let payload = try XCTUnwrap(Self.decodePayload(from: assistant.content))
        XCTAssertTrue(payload.answer.lowercased().contains("не знаю"))
        XCTAssertTrue(payload.answer.lowercased().contains("уточните"))
        XCTAssertFalse(payload.sources.isEmpty)
        XCTAssertFalse(payload.quotes.isEmpty)
        XCTAssertEqual(payload.sources.first?.source, "rag://no-matches")
        XCTAssertEqual(payload.quotes.first?.source, "rag://no-matches")

        let sendCalls = await llmClient.sendCallCount()
        XCTAssertEqual(sendCalls, 0)
    }

    private func makeUseCase(
        llmClient: LLMClientProtocol,
        ragSpy: RAGFacadeSpy
    ) -> (useCase: SendMessageUseCase, settingsRepository: MockSettingsRepository) {
        let settingsRepository = MockSettingsRepository()
        let messageRepository = MockMessageRepository()
        let shortTermRepository = MockShortTermMemoryRepository()
        let workingMemoryRepository = MockWorkingMemoryRepository()
        let longTermMemoryRepository = MockLongTermMemoryRepository()
        let metricsRepository = MockMetricsRepository()

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
        return (useCase: useCase, settingsRepository: settingsRepository)
    }

    static func makeSearchResult(content: String, score: Float) -> SearchResult {
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

    private static func decodePayload(from json: String) -> TestRAGPayload? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TestRAGPayload.self, from: data)
    }
}

private actor RAGFacadeSpy: RAGUseCaseFacadeProtocol {
    private(set) var indexCallCount = 0
    private(set) var searchCallCount = 0
    private(set) var lastSearchTopK: Int?
    private let searchResults: [SearchResult]

    init(searchResults: [SearchResult]) {
        self.searchResults = searchResults
    }

    func index(documents: [URL], strategy: ChunkingStrategyType) async throws -> IndexingSummary {
        _ = documents
        _ = strategy
        indexCallCount += 1
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

private actor LLMClientSpy: LLMClientProtocol {
    private var request: LLMRequest?
    private var calls = 0

    func send(request: LLMRequest) async throws -> LLMResponse {
        self.request = request
        calls += 1
        return LLMResponse(
            content: "Reply",
            inputTokens: 10,
            outputTokens: 6,
            latencyMs: 40
        )
    }

    func capturedRequest() -> LLMRequest? {
        request
    }

    func sendCallCount() -> Int {
        calls
    }
}

private struct TestRAGPayload: Decodable {
    let answer: String
    let sources: [TestRAGSource]
    let quotes: [TestRAGQuote]
}

private struct TestRAGSource: Decodable {
    let source: String
    let section: String?
    let chunkID: String

    private enum CodingKeys: String, CodingKey {
        case source
        case section
        case chunkID = "chunk_id"
    }
}

private struct TestRAGQuote: Decodable {
    let chunkID: String
    let source: String
    let section: String?
    let text: String

    private enum CodingKeys: String, CodingKey {
        case chunkID = "chunk_id"
        case source
        case section
        case text
    }
}

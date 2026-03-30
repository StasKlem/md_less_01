import XCTest
@testable import LightNeiroClient

final class ProjectHelpUseCaseTests: XCTestCase {
    func testExecuteUsesDocumentationAndProjectBranchInPrompt() async throws {
        let settingsRepository = MockSettingsRepository()
        try await settingsRepository.saveSettings(settings: .default)

        let llmClient = ProjectHelpLLMClientSpy(
            response: LLMResponse(
                content: "Готовый ответ",
                inputTokens: 12,
                outputTokens: 24,
                latencyMs: 90
            )
        )
        let ragFacade = ProjectHelpRAGFacadeSpy(
            searchResults: [
                Self.makeSearchResult(
                    source: "/tmp/README.md",
                    section: "Архитектура",
                    content: "App, Domain, Data, Presentation"
                ),
                Self.makeSearchResult(
                    source: "/tmp/Doc/help.md",
                    section: "Команды",
                    content: "/help отвечает по документации"
                )
            ]
        )
        let branchService = ProjectHelpBranchServiceSpy(result: .success("main"))

        let useCase = ProjectHelpUseCase(
            settingsRepository: settingsRepository,
            llmClient: llmClient,
            ragUseCaseFacade: ragFacade,
            projectContextService: branchService,
            ragDocumentsProvider: { [] },
            initialIndexedRAGStrategy: .structural
        )

        let answer = await useCase.execute(question: "Как устроен проект?")

        XCTAssertEqual(answer, "Готовый ответ")
        let searchCallCount = await ragFacade.searchCallCount
        let lastTopK = await ragFacade.lastTopK
        let lastQuery = await ragFacade.lastQuery ?? ""
        XCTAssertEqual(searchCallCount, 1)
        XCTAssertEqual(lastTopK, 4)
        XCTAssertTrue(lastQuery.contains("Как устроен проект?"))

        let capturedRequest = await llmClient.capturedRequest
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertTrue(request.systemPrompt.contains("main"))
        XCTAssertTrue(request.systemPrompt.contains("README.md"))
        XCTAssertTrue(request.systemPrompt.contains("LightNeiroClient/Doc"))
        XCTAssertTrue(request.systemPrompt.contains("Как устроен проект?"))
        XCTAssertTrue(request.systemPrompt.contains("App, Domain, Data, Presentation"))
        XCTAssertTrue(request.systemPrompt.contains("/help отвечает по документации"))
    }

    func testExecuteFallsBackWhenLLMIsUnavailable() async throws {
        let settingsRepository = MockSettingsRepository()
        try await settingsRepository.saveSettings(settings: .default)

        let llmClient = ProjectHelpLLMClientSpy(
            error: StubError.failed
        )
        let ragFacade = ProjectHelpRAGFacadeSpy(
            searchResults: [
                Self.makeSearchResult(
                    source: "/tmp/README.md",
                    section: "Структура",
                    content: "App, Domain, Data, Presentation"
                )
            ]
        )
        let branchService = ProjectHelpBranchServiceSpy(
            result: .failure(StubError.failed)
        )

        let useCase = ProjectHelpUseCase(
            settingsRepository: settingsRepository,
            llmClient: llmClient,
            ragUseCaseFacade: ragFacade,
            projectContextService: branchService,
            ragDocumentsProvider: { [] },
            initialIndexedRAGStrategy: .structural
        )

        let answer = await useCase.execute(question: nil)

        XCTAssertTrue(answer.contains("Краткий обзор проекта LightNeiroClient:"))
        XCTAssertTrue(answer.contains("Текущая git-ветка: не удалось определить."))
        XCTAssertTrue(answer.contains("README.md"))
    }

    private static func makeSearchResult(source: String, section: String, content: String) -> SearchResult {
        let chunk = DocumentChunk(
            id: UUID(),
            content: content,
            embedding: [0, 1, 0],
            source: source,
            title: nil,
            section: section,
            offset: 0
        )
        return SearchResult(chunk: chunk, score: 0.92)
    }
}

private enum StubError: LocalizedError {
    case failed

    var errorDescription: String? {
        "request failed"
    }
}

private actor ProjectHelpLLMClientSpy: LLMClientProtocol {
    let response: LLMResponse?
    let error: Error?
    private(set) var capturedRequest: LLMRequest?

    init(response: LLMResponse) {
        self.response = response
        self.error = nil
    }

    init(error: Error) {
        self.response = nil
        self.error = error
    }

    func send(request: LLMRequest) async throws -> LLMResponse {
        capturedRequest = request
        if let error {
            throw error
        }
        return response ?? LLMResponse(content: "", inputTokens: 0, outputTokens: 0, latencyMs: 0)
    }
}

private actor ProjectHelpRAGFacadeSpy: RAGUseCaseFacadeProtocol {
    let searchResults: [SearchResult]
    private(set) var searchCallCount = 0
    private(set) var lastQuery: String?
    private(set) var lastTopK: Int?
    private(set) var indexCallCount = 0

    init(searchResults: [SearchResult]) {
        self.searchResults = searchResults
    }

    func index(documents _: [URL], strategy _: ChunkingStrategyType) async throws -> IndexingSummary {
        indexCallCount += 1
        return IndexingSummary(documentCount: 0, chunkCount: 0, indexingDurationMs: 0)
    }

    func search(query: String, topK: Int) async throws -> [SearchResult] {
        searchCallCount += 1
        lastQuery = query
        lastTopK = topK
        return Array(searchResults.prefix(topK))
    }

    func compare(
        strategies _: [ChunkingStrategyType],
        dataset _: [URL],
        evaluationCases _: [ChunkingEvaluationCase],
        topK _: Int
    ) async throws -> ChunkingComparisonReport {
        ChunkingComparisonReport(metrics: [], recommendedDefault: .structural)
    }

    func resetIndex() async throws {}
}

private actor ProjectHelpBranchServiceSpy: ProjectGitBranchServiceProtocol {
    let result: Result<String, Error>

    init(result: Result<String, Error>) {
        self.result = result
    }

    func fetchCurrentGitBranch(serverURL _: URL) async throws -> String {
        try result.get()
    }
}

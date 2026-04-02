import XCTest
@testable import LightNeiroClient

final class ProjectReviewUseCaseTests: XCTestCase {
    func testExecuteBuildsReviewFromChangesAndRAGEvidence() async throws {
        let settingsRepository = MockSettingsRepository()
        try await settingsRepository.saveSettings(settings: .default)

        let llmClient = ProjectReviewLLMClientSpy(
            response: LLMResponse(
                content: "1. Критические замечания\n2. Риски\n3. Замечания\n4. Краткий итог",
                inputTokens: 10,
                outputTokens: 20,
                latencyMs: 50
            )
        )
        let ragFacade = ProjectReviewRAGFacadeSpy(
            searchResults: [
                Self.makeSearchResult(
                    source: "/tmp/README.md",
                    section: "Архитектура",
                    content: "Presentation depends on Domain"
                )
            ]
        )
        let contextService = ProjectReviewContextServiceSpy(
            changes: ProjectUncommittedChangesContext(
                files: ["LightNeiroClient/Presentation/Chat/ChatViewModel.swift"],
                diff: "diff --git a/ChatViewModel.swift b/ChatViewModel.swift",
                diagnosticMessage: nil
            )
        )

        let useCase = ProjectReviewTaskOrchestrator(
            settingsRepository: settingsRepository,
            llmClient: llmClient,
            ragUseCaseFacade: ragFacade,
            projectContextService: contextService,
            ragDocumentsProvider: { [] },
            initialIndexedRAGStrategy: .structural
        )

        let result = await useCase.start(
            sessionID: UUID(),
            branchID: UUID(),
            focus: "архитектура"
        )

        XCTAssertEqual(result.snapshot.state, .idle)
        XCTAssertEqual(result.reviewText, "1. Критические замечания\n2. Риски\n3. Замечания\n4. Краткий итог")
        XCTAssertTrue(result.systemMessages.contains(where: { $0.contains("Получение diff и изменённых файлов") }))
        XCTAssertTrue(result.systemMessages.contains(where: { $0.contains("Работа с RAG") }))
        XCTAssertTrue(result.systemMessages.contains(where: { $0.contains("Анализ изменений и генерация текста ревью") }))

        let searchCallCount = await ragFacade.searchCallCount
        let lastQuery = await ragFacade.lastQuery ?? ""
        XCTAssertEqual(searchCallCount, 1)
        XCTAssertTrue(lastQuery.contains("ChatViewModel.swift"))
        XCTAssertTrue(lastQuery.contains("diff --git"))

        let capturedRequest = await llmClient.capturedRequest
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertTrue(request.systemPrompt.contains("UNCOMMITTED_FILES"))
        XCTAssertTrue(request.systemPrompt.contains("ChatViewModel.swift"))
        XCTAssertTrue(request.systemPrompt.contains("Presentation depends on Domain"))
        XCTAssertTrue(request.systemPrompt.contains("Фокус ревью: архитектура"))
    }

    func testExecuteReturnsIdleWhenNoUncommittedChangesExist() async throws {
        let settingsRepository = MockSettingsRepository()
        try await settingsRepository.saveSettings(settings: .default)

        let llmClient = ProjectReviewLLMClientSpy(
            response: LLMResponse(
                content: "unused",
                inputTokens: 0,
                outputTokens: 0,
                latencyMs: 0
            )
        )
        let ragFacade = ProjectReviewRAGFacadeSpy(searchResults: [])
        let contextService = ProjectReviewContextServiceSpy(
            changes: ProjectUncommittedChangesContext(
                files: [],
                diff: "",
                diagnosticMessage: nil
            )
        )

        let useCase = ProjectReviewTaskOrchestrator(
            settingsRepository: settingsRepository,
            llmClient: llmClient,
            ragUseCaseFacade: ragFacade,
            projectContextService: contextService,
            ragDocumentsProvider: { [] },
            initialIndexedRAGStrategy: .structural
        )

        let result = await useCase.start(
            sessionID: UUID(),
            branchID: UUID(),
            focus: nil
        )

        XCTAssertEqual(result.snapshot.state, .idle)
        XCTAssertEqual(result.reviewText, "Незакоммиченных изменений не найдено.")
        XCTAssertEqual(result.systemMessages.count, 1)
        XCTAssertTrue(result.systemMessages.first?.contains("Получение diff и изменённых файлов") == true)
        let searchCallCount = await ragFacade.searchCallCount
        XCTAssertEqual(searchCallCount, 0)
    }

    func testExecuteBuildsFallbackReviewWhenLLMIsUnavailable() async throws {
        let settingsRepository = MockSettingsRepository()
        try await settingsRepository.saveSettings(settings: .default)

        let llmClient = ProjectReviewThrowingLLMClientSpy(
            error: URLError(.cannotConnectToHost)
        )
        let ragFacade = ProjectReviewRAGFacadeSpy(
            searchResults: [
                Self.makeSearchResult(
                    source: "/tmp/Docs/Architecture.md",
                    section: "Review",
                    content: "Presentation layer should depend on Domain only"
                )
            ]
        )
        let contextService = ProjectReviewContextServiceSpy(
            changes: ProjectUncommittedChangesContext(
                files: ["LightNeiroClient/Domain/UseCases/ProjectReviewUseCases.swift"],
                diff: "diff --git a/ProjectReviewUseCases.swift b/ProjectReviewUseCases.swift",
                diagnosticMessage: nil
            )
        )

        let useCase = ProjectReviewTaskOrchestrator(
            settingsRepository: settingsRepository,
            llmClient: llmClient,
            ragUseCaseFacade: ragFacade,
            projectContextService: contextService,
            ragDocumentsProvider: { [] },
            initialIndexedRAGStrategy: .structural
        )

        let result = await useCase.start(
            sessionID: UUID(),
            branchID: UUID(),
            focus: "архитектура"
        )

        XCTAssertEqual(result.snapshot.state, .idle)
        XCTAssertTrue(result.reviewText.contains("Локальный разбор изменений проекта LightNeiroClient"))
        XCTAssertTrue(result.reviewText.contains("ProjectReviewUseCases.swift"))
        XCTAssertTrue(result.reviewText.contains("RAG-контекст"))
        XCTAssertTrue(result.reviewText.contains("Краткий итог: локальное ревью сформировано без ответа LLM."))
        XCTAssertTrue(result.systemMessages.contains(where: { $0.contains("Анализ изменений и генерация текста ревью") }))
        XCTAssertFalse(result.systemMessages.contains(where: { $0.contains("LLM") }))

        let searchCallCount = await ragFacade.searchCallCount
        XCTAssertEqual(searchCallCount, 1)
    }

    func testExecuteBuildsFallbackReviewWhenRAGIsNotConfigured() async throws {
        let settingsRepository = MockSettingsRepository()
        try await settingsRepository.saveSettings(settings: .default)

        let llmClient = ProjectReviewThrowingLLMClientSpy(
            error: URLError(.cannotConnectToHost)
        )
        let contextService = ProjectReviewContextServiceSpy(
            changes: ProjectUncommittedChangesContext(
                files: ["LightNeiroClient/Domain/UseCases/ProjectReviewUseCases.swift"],
                diff: "diff --git a/ProjectReviewUseCases.swift b/ProjectReviewUseCases.swift",
                diagnosticMessage: nil
            )
        )

        let useCase = ProjectReviewTaskOrchestrator(
            settingsRepository: settingsRepository,
            llmClient: llmClient,
            ragUseCaseFacade: nil,
            projectContextService: contextService,
            ragDocumentsProvider: { [] },
            initialIndexedRAGStrategy: .structural
        )

        let result = await useCase.start(
            sessionID: UUID(),
            branchID: UUID(),
            focus: nil
        )

        XCTAssertEqual(result.snapshot.state, .idle)
        XCTAssertTrue(result.reviewText.contains("RAG-контекст не настроен."))
        XCTAssertTrue(result.reviewText.contains("Краткий итог: локальное ревью сформировано без ответа LLM."))
    }

    func testExecuteBuildsFallbackReviewWhenRAGReturnsNoResults() async throws {
        let settingsRepository = MockSettingsRepository()
        try await settingsRepository.saveSettings(settings: .default)

        let llmClient = ProjectReviewThrowingLLMClientSpy(
            error: URLError(.cannotConnectToHost)
        )
        let ragFacade = ProjectReviewRAGFacadeSpy(searchResults: [])
        let contextService = ProjectReviewContextServiceSpy(
            changes: ProjectUncommittedChangesContext(
                files: ["LightNeiroClient/Domain/UseCases/ProjectReviewUseCases.swift"],
                diff: "diff --git a/ProjectReviewUseCases.swift b/ProjectReviewUseCases.swift",
                diagnosticMessage: nil
            )
        )

        let useCase = ProjectReviewTaskOrchestrator(
            settingsRepository: settingsRepository,
            llmClient: llmClient,
            ragUseCaseFacade: ragFacade,
            projectContextService: contextService,
            ragDocumentsProvider: { [] },
            initialIndexedRAGStrategy: .structural
        )

        let result = await useCase.start(
            sessionID: UUID(),
            branchID: UUID(),
            focus: nil
        )

        XCTAssertEqual(result.snapshot.state, .idle)
        XCTAssertTrue(result.reviewText.contains("RAG-контекст не нашёл релевантных фрагментов."))
        let searchCallCount = await ragFacade.searchCallCount
        XCTAssertEqual(searchCallCount, 1)
    }

    func testExecuteBuildsFallbackReviewWhenRAGFails() async throws {
        let settingsRepository = MockSettingsRepository()
        try await settingsRepository.saveSettings(settings: .default)

        let llmClient = ProjectReviewThrowingLLMClientSpy(
            error: URLError(.cannotConnectToHost)
        )
        let ragFacade = ProjectReviewThrowingRAGFacadeSpy(
            error: URLError(.cannotConnectToHost)
        )
        let contextService = ProjectReviewContextServiceSpy(
            changes: ProjectUncommittedChangesContext(
                files: ["LightNeiroClient/Domain/UseCases/ProjectReviewUseCases.swift"],
                diff: "diff --git a/ProjectReviewUseCases.swift b/ProjectReviewUseCases.swift",
                diagnosticMessage: nil
            )
        )

        let useCase = ProjectReviewTaskOrchestrator(
            settingsRepository: settingsRepository,
            llmClient: llmClient,
            ragUseCaseFacade: ragFacade,
            projectContextService: contextService,
            ragDocumentsProvider: { [] },
            initialIndexedRAGStrategy: .structural
        )

        let result = await useCase.start(
            sessionID: UUID(),
            branchID: UUID(),
            focus: nil
        )

        XCTAssertEqual(result.snapshot.state, .idle)
        XCTAssertTrue(result.reviewText.contains("RAG-контекст временно недоступен."))
    }

    func testExecuteIgnoresRAGFailuresAndContinuesReviewGeneration() async throws {
        let settingsRepository = MockSettingsRepository()
        try await settingsRepository.saveSettings(settings: .default)

        let llmClient = ProjectReviewLLMClientSpy(
            response: LLMResponse(
                content: "1. Критические замечания\n2. Риски\n3. Замечания\n4. Краткий итог",
                inputTokens: 10,
                outputTokens: 20,
                latencyMs: 50
            )
        )
        let ragFacade = ProjectReviewThrowingRAGFacadeSpy(
            error: URLError(.cannotConnectToHost)
        )
        let contextService = ProjectReviewContextServiceSpy(
            changes: ProjectUncommittedChangesContext(
                files: ["LightNeiroClient/Presentation/Chat/ChatViewModel.swift"],
                diff: "diff --git a/ChatViewModel.swift b/ChatViewModel.swift",
                diagnosticMessage: nil
            )
        )

        let useCase = ProjectReviewTaskOrchestrator(
            settingsRepository: settingsRepository,
            llmClient: llmClient,
            ragUseCaseFacade: ragFacade,
            projectContextService: contextService,
            ragDocumentsProvider: { [] },
            initialIndexedRAGStrategy: .structural
        )

        let result = await useCase.start(
            sessionID: UUID(),
            branchID: UUID(),
            focus: nil
        )

        XCTAssertEqual(result.snapshot.state, .idle)
        XCTAssertEqual(result.reviewText, "1. Критические замечания\n2. Риски\n3. Замечания\n4. Краткий итог")
        XCTAssertFalse(result.systemMessages.contains(where: { $0.contains("RAG-контекст") }))
        XCTAssertFalse(result.systemMessages.contains(where: { $0.contains("RAG") && $0.contains("ошиб") }))
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

private actor ProjectReviewLLMClientSpy: LLMClientProtocol {
    let response: LLMResponse
    private(set) var capturedRequest: LLMRequest?

    init(response: LLMResponse) {
        self.response = response
    }

    func send(request: LLMRequest) async throws -> LLMResponse {
        capturedRequest = request
        return response
    }
}

private actor ProjectReviewThrowingLLMClientSpy: LLMClientProtocol {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func send(request _: LLMRequest) async throws -> LLMResponse {
        throw error
    }
}

private actor ProjectReviewRAGFacadeSpy: RAGUseCaseFacadeProtocol {
    let searchResults: [SearchResult]
    private(set) var searchCallCount = 0
    private(set) var lastQuery: String?

    init(searchResults: [SearchResult]) {
        self.searchResults = searchResults
    }

    func index(documents _: [URL], strategy _: ChunkingStrategyType) async throws -> IndexingSummary {
        IndexingSummary(documentCount: 0, chunkCount: 0, indexingDurationMs: 0)
    }

    func search(query: String, topK: Int) async throws -> [SearchResult] {
        searchCallCount += 1
        lastQuery = query
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

private actor ProjectReviewThrowingRAGFacadeSpy: RAGUseCaseFacadeProtocol {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func index(documents _: [URL], strategy _: ChunkingStrategyType) async throws -> IndexingSummary {
        throw error
    }

    func search(query _: String, topK _: Int) async throws -> [SearchResult] {
        throw error
    }

    func compare(
        strategies _: [ChunkingStrategyType],
        dataset _: [URL],
        evaluationCases _: [ChunkingEvaluationCase],
        topK _: Int
    ) async throws -> ChunkingComparisonReport {
        throw error
    }

    func resetIndex() async throws {
        throw error
    }
}

private actor ProjectReviewContextServiceSpy: ProjectGitBranchServiceProtocol {
    let changes: ProjectUncommittedChangesContext

    init(changes: ProjectUncommittedChangesContext) {
        self.changes = changes
    }

    func fetchCurrentGitBranch(serverURL _: URL) async throws -> ProjectGitBranchContext {
        ProjectGitBranchContext(branch: "main", diagnosticMessage: nil)
    }

    func fetchProjectFiles(serverURL _: URL) async throws -> ProjectFilesContext {
        ProjectFilesContext(files: changes.files, diagnosticMessage: nil)
    }

    func fetchUncommittedChanges(serverURL _: URL) async throws -> ProjectUncommittedChangesContext {
        changes
    }
}

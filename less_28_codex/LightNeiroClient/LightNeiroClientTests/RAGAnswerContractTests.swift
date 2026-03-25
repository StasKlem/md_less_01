import XCTest
@testable import LightNeiroClient

@MainActor
final class RAGAnswerContractTests: XCTestCase {
    func testRAGContractForTenQuestionsContainsSourcesQuotesAndSemanticAlignment() async throws {
        let llmClient = ContractLLMClientSpy(responseContent: "{invalid-json")
        let ragSpy = ContractRAGFacadeSpy(resultsByQuery: makeTop10QueryResults())
        let sut = makeUseCase(llmClient: llmClient, ragSpy: ragSpy)

                var settings = LLMSettings.default
        settings.isRAGEnabled = true
        settings.isMemoryEnabled = false
        settings.isRAGPostFilteringEnabled = true
        settings.ragTopKBeforeFiltering = 6
        settings.ragTopKAfterFiltering = 3
        settings.ragRelevanceThreshold = 0.70
        try await sut.settingsRepository.saveSettings(settings: settings)

        for query in Self.top10Questions {
            let assistant = try await sut.useCase.execute(
                userText: query,
                assistantInstruction: nil
            )

            let payload = try XCTUnwrap(Self.decodePayload(from: assistant.content), "Ответ должен быть валидным JSON")
            XCTAssertFalse(payload.sources.isEmpty, "В каждом ответе ожидаются источники")
            XCTAssertFalse(payload.quotes.isEmpty, "В каждом ответе ожидаются цитаты")

            let sourceChunkIDs = Set(payload.sources.map(\.chunkID))
            XCTAssertFalse(sourceChunkIDs.isEmpty)
            XCTAssertTrue(payload.quotes.allSatisfy { sourceChunkIDs.contains($0.chunkID) })
            XCTAssertTrue(Self.hasSemanticOverlap(answer: payload.answer, quotes: payload.quotes))
        }
    }

    func testRAGContractFallsBackToLLMWhenRelevanceBelowThreshold() async throws {
        let llmClient = ContractLLMClientSpy(responseContent: "{invalid-json")
        let lowResult = Self.makeSearchResult(
            content: "Нерелевантный общий текст",
            score: 0.25,
            section: "Noise"
        )
        let ragSpy = ContractRAGFacadeSpy(resultsByQuery: ["Какой режим SQLite рекомендуется для производительности записи?": [lowResult]])
        let sut = makeUseCase(llmClient: llmClient, ragSpy: ragSpy)

                var settings = LLMSettings.default
        settings.isRAGEnabled = true
        settings.isMemoryEnabled = false
        settings.isRAGPostFilteringEnabled = true
        settings.ragTopKBeforeFiltering = 4
        settings.ragTopKAfterFiltering = 2
        settings.ragRelevanceThreshold = 0.90
        try await sut.settingsRepository.saveSettings(settings: settings)

        let assistant = try await sut.useCase.execute(
                userText: "Какой режим SQLite рекомендуется для производительности записи?",
            assistantInstruction: nil
        )

        XCTAssertEqual(assistant.content, "{invalid-json")

        let llmCalls = await llmClient.sendCallCount()
        XCTAssertEqual(llmCalls, 1)
    }

    private func makeUseCase(
        llmClient: LLMClientProtocol,
        ragSpy: ContractRAGFacadeSpy
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
                [URL(fileURLWithPath: "/tmp/mobile_system_design_guide.md")]
            },
            initialIndexedRAGStrategy: .structural
        )
        return (useCase: useCase, settingsRepository: settingsRepository)
    }

    private func makeTop10QueryResults() -> [String: [SearchResult]] {
        [
            "Какой режим SQLite рекомендуется для производительности записи?": [
                Self.makeSearchResult(content: "Для производительности записи в SQLite рекомендуется режим WAL.", score: 0.94, section: "SQLite"),
                Self.makeSearchResult(content: "PRAGMA journal_mode=WAL помогает параллельному чтению и записи.", score: 0.90, section: "SQLite")
            ],
            "Что такое SSL Pinning и зачем он нужен?": [
                Self.makeSearchResult(content: "SSL Pinning фиксирует сертификат сервера и защищает от MITM-атак.", score: 0.93, section: "Security"),
                Self.makeSearchResult(content: "Пиннинг полезен для критичных API и мобильных клиентов.", score: 0.88, section: "Security")
            ],
            "Какие три основных архитектурных паттерна перечислены в тексте?": [
                Self.makeSearchResult(content: "В документе перечислены Clean Architecture, Offline-First и SSL Pinning.", score: 0.95, section: "Architecture"),
                Self.makeSearchResult(content: "Эти паттерны помогают масштабировать мобильные приложения.", score: 0.86, section: "Architecture")
            ],
            "Какой формат изображений рекомендуется использовать вместо PNG?": [
                Self.makeSearchResult(content: "Для экономии трафика рекомендуется использовать WebP вместо PNG.", score: 0.91, section: "Performance"),
                Self.makeSearchResult(content: "WebP снижает размер ассетов при сопоставимом качестве.", score: 0.87, section: "Performance")
            ],
            "Где должны храниться Refresh токены на iOS?": [
                Self.makeSearchResult(content: "Refresh токены на iOS следует хранить в Keychain.", score: 0.96, section: "Security"),
                Self.makeSearchResult(content: "Keychain предоставляет защищенное хранение секретов.", score: 0.92, section: "Security")
            ],
            "В чём разница между стратегиями Polling и WebSockets?": [
                Self.makeSearchResult(content: "Polling делает периодические запросы, WebSockets держат постоянное двустороннее соединение.", score: 0.94, section: "Networking"),
                Self.makeSearchResult(content: "WebSockets уменьшают задержку событий по сравнению с polling.", score: 0.90, section: "Networking")
            ],
            "Сравни MVVM и MVI по принципу потока данных.": [
                Self.makeSearchResult(content: "MVVM допускает двунаправленные биндинги, MVI строится вокруг однонаправленного потока данных.", score: 0.93, section: "Architecture"),
                Self.makeSearchResult(content: "MVI упрощает воспроизводимость состояний через immutable state.", score: 0.88, section: "Architecture")
            ],
            "Какие плюсы и минусы у GraphQL по сравнению с REST?": [
                Self.makeSearchResult(content: "GraphQL уменьшает overfetching, но усложняет кеширование и контроль запросов.", score: 0.92, section: "API"),
                Self.makeSearchResult(content: "REST проще для CDN и HTTP-кешей, но менее гибок по форме данных.", score: 0.89, section: "API")
            ],
            "Какая версия протокола TLS запрещена к использованию?": [
                Self.makeSearchResult(content: "В тексте упоминается использование TLS 1.3, но прямой запрет старых версий не формулируется.", score: 0.91, section: "Security"),
                Self.makeSearchResult(content: "Документ не задает список запрещенных версий TLS.", score: 0.87, section: "Security")
            ],
            "Какая библиотека для работы с БД рекомендуется для Flutter?": [
                Self.makeSearchResult(content: "Документ сфокусирован на iOS и Android и не содержит рекомендаций по Flutter-библиотекам БД.", score: 0.90, section: "Scope"),
                Self.makeSearchResult(content: "Информация о Flutter в разделе базы данных отсутствует.", score: 0.86, section: "Scope")
            ]
        ]
    }

    static func makeSearchResult(content: String, score: Float, section: String) -> SearchResult {
        let chunk = DocumentChunk(
            id: UUID(),
            content: content,
            embedding: [0, 1, 0, 1],
            source: "/tmp/mobile_system_design_guide.md",
            title: "mobile_system_design_guide",
            section: section,
            offset: 0
        )
        return SearchResult(chunk: chunk, score: score)
    }

    private static func decodePayload(from json: String) -> TestRAGPayload? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TestRAGPayload.self, from: data)
    }

    private static func hasSemanticOverlap(answer: String, quotes: [TestRAGQuote]) -> Bool {
        let answerTokens = meaningfulTokens(in: answer)
        guard !answerTokens.isEmpty else { return false }

        let allQuotes = quotes.map(\.text).joined(separator: " ")
        let quoteTokens = meaningfulTokens(in: allQuotes)
        guard !quoteTokens.isEmpty else { return false }

        let overlapCount = answerTokens.intersection(quoteTokens).count
        let overlapRatio = Double(overlapCount) / Double(answerTokens.count)
        return overlapRatio >= 0.30
    }

    static func meaningfulTokens(in text: String) -> Set<String> {
        let lowercased = text.lowercased()
        let separators = CharacterSet.alphanumerics.inverted
        let rawTokens = lowercased
            .components(separatedBy: separators)
            .filter { $0.count >= 4 }

        let stopWords: Set<String> = [
            "согласно", "найденным", "источникам", "ответ", "должен", "быть", "если",
            "когда", "который", "которые", "этого", "этот", "также", "вопрос", "please",
            "with", "from", "that", "this", "have", "there", "where"
        ]
        return Set(rawTokens.filter { !stopWords.contains($0) })
    }

    static let top10Questions: [String] = [
        "Какой режим SQLite рекомендуется для производительности записи?",
        "Что такое SSL Pinning и зачем он нужен?",
        "Какие три основных архитектурных паттерна перечислены в тексте?",
        "Какой формат изображений рекомендуется использовать вместо PNG?",
        "Где должны храниться Refresh токены на iOS?",
        "В чём разница между стратегиями Polling и WebSockets?",
        "Сравни MVVM и MVI по принципу потока данных.",
        "Какие плюсы и минусы у GraphQL по сравнению с REST?",
        "Какая версия протокола TLS запрещена к использованию?",
        "Какая библиотека для работы с БД рекомендуется для Flutter?"
    ]
}

private actor ContractRAGFacadeSpy: RAGUseCaseFacadeProtocol {
    private let resultsByQuery: [String: [SearchResult]]

    init(resultsByQuery: [String: [SearchResult]]) {
        self.resultsByQuery = resultsByQuery
    }

    func index(documents: [URL], strategy: ChunkingStrategyType) async throws -> IndexingSummary {
        _ = documents
        _ = strategy
        return IndexingSummary(documentCount: 0, chunkCount: 0, indexingDurationMs: 0)
    }

    func search(query: String, topK: Int) async throws -> [SearchResult] {
        let results = resultsByQuery[query] ?? []
        return Array(results.prefix(max(1, topK)))
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

private actor ContractLLMClientSpy: LLMClientProtocol {
    private let responseContent: String
    private var calls = 0

    init(responseContent: String) {
        self.responseContent = responseContent
    }

    func send(request: LLMRequest) async throws -> LLMResponse {
        _ = request
        calls += 1
        return LLMResponse(
            content: responseContent,
            inputTokens: 11,
            outputTokens: 7,
            latencyMs: 12
        )
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

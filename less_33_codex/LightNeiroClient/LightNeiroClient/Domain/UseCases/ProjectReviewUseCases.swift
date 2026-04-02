import Foundation

final class StartProjectReviewTaskUseCase: StartProjectReviewTaskUseCaseProtocol {
    private let orchestrator: ProjectReviewTaskOrchestrator

    init(orchestrator: ProjectReviewTaskOrchestrator) {
        self.orchestrator = orchestrator
    }

    func execute(
        sessionID: UUID,
        branchID: UUID,
        focus: String?
    ) async -> ProjectReviewTaskTurnResult {
        await orchestrator.start(
            sessionID: sessionID,
            branchID: branchID,
            focus: focus
        )
    }
}

final class ProjectReviewTaskOrchestrator {
    private static let ragLogCategory = "review.rag"
    private static let llmLogCategory = "review.llm"
    private let settingsRepository: SettingsRepositoryProtocol
    private let llmClient: LLMClientProtocol
    private let ragUseCaseFacade: RAGUseCaseFacadeProtocol?
    private let projectContextService: ProjectGitBranchServiceProtocol
    private let projectChangesEndpointURL: URL
    private let ragDocumentsProvider: @Sendable () -> [URL]
    private let ragIndexState: ProjectReviewRAGIndexState

    init(
        settingsRepository: SettingsRepositoryProtocol,
        llmClient: LLMClientProtocol,
        ragUseCaseFacade: RAGUseCaseFacadeProtocol?,
        projectContextService: ProjectGitBranchServiceProtocol,
        projectChangesEndpointURL: URL = URL(string: "stdio://project")!,
        ragDocumentsProvider: @escaping @Sendable () -> [URL] = { [] },
        initialIndexedRAGStrategy: ChunkingStrategyType? = nil
    ) {
        self.settingsRepository = settingsRepository
        self.llmClient = llmClient
        self.ragUseCaseFacade = ragUseCaseFacade
        self.projectContextService = projectContextService
        self.projectChangesEndpointURL = projectChangesEndpointURL
        self.ragDocumentsProvider = ragDocumentsProvider
        self.ragIndexState = ProjectReviewRAGIndexState(initialStrategy: initialIndexedRAGStrategy)
    }

    func start(
        sessionID: UUID,
        branchID: UUID,
        focus: String?
    ) async -> ProjectReviewTaskTurnResult {
        let settings = (try? await settingsRepository.fetchSettings()) ?? .default
        let normalizedFocus = focus?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let reviewFocus = normalizedFocus?.isEmpty == false ? normalizedFocus : nil

        let loadingState = ProjectReviewTaskSnapshot(
            schemaVersion: ProjectReviewTaskSnapshot.schemaVersionCurrent,
            sessionID: sessionID,
            branchID: branchID,
            state: .collectingChanges,
            context: ProjectReviewTaskContext(
                focus: reviewFocus,
                changedFiles: [],
                diff: "",
                evidence: [],
                reviewText: nil,
                updatedAt: Date()
            ),
            updatedAt: Date()
        )
        var systemMessages: [String] = []
        systemMessages.append(stateChangeMessage(for: loadingState.state))

        let changes = await fetchUncommittedChanges()
        if let diagnosticMessage = changes.diagnosticMessage {
            systemMessages.append(diagnosticMessage)
        }
        if changes.files.isEmpty && changes.diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let snapshot = ProjectReviewTaskSnapshot(
                schemaVersion: ProjectReviewTaskSnapshot.schemaVersionCurrent,
                sessionID: sessionID,
                branchID: branchID,
                state: .idle,
                context: ProjectReviewTaskContext(
                    focus: reviewFocus,
                    changedFiles: [],
                    diff: "",
                    evidence: [],
                    reviewText: "Незакоммиченных изменений не найдено.",
                    updatedAt: Date()
                ),
                updatedAt: Date()
            )
            return ProjectReviewTaskTurnResult(
                snapshot: snapshot,
                reviewText: "Незакоммиченных изменений не найдено.",
                systemMessages: systemMessages
            )
        }

        let changesState = ProjectReviewTaskSnapshot(
            schemaVersion: ProjectReviewTaskSnapshot.schemaVersionCurrent,
            sessionID: sessionID,
            branchID: branchID,
            state: .workingWithRAG,
            context: ProjectReviewTaskContext(
                focus: reviewFocus,
                changedFiles: changes.files,
                diff: changes.diff,
                evidence: [],
                reviewText: nil,
                updatedAt: Date()
            ),
            updatedAt: Date()
        )
        systemMessages.append(stateChangeMessage(for: changesState.state))

        let evidenceResult = await collectEvidence(
            changedFiles: changes.files,
            diff: changes.diff,
            strategy: settings.ragChunkingStrategy
        )

        let evidenceState = ProjectReviewTaskSnapshot(
            schemaVersion: ProjectReviewTaskSnapshot.schemaVersionCurrent,
            sessionID: sessionID,
            branchID: branchID,
            state: .analyzingChanges,
            context: ProjectReviewTaskContext(
                focus: reviewFocus,
                changedFiles: changes.files,
                diff: changes.diff,
                evidence: evidenceResult.evidence,
                reviewText: nil,
                updatedAt: Date()
            ),
            updatedAt: Date()
        )
        systemMessages.append(stateChangeMessage(for: evidenceState.state))

        let generationResult = await generateReviewResult(
            focus: reviewFocus,
            changes: changes,
            evidence: evidenceResult.evidence,
            ragState: evidenceResult,
            settings: settings
        )

        let finishedSnapshot = ProjectReviewTaskSnapshot(
            schemaVersion: ProjectReviewTaskSnapshot.schemaVersionCurrent,
            sessionID: sessionID,
            branchID: branchID,
            state: .idle,
            context: ProjectReviewTaskContext(
                focus: reviewFocus,
                changedFiles: changes.files,
                diff: changes.diff,
                evidence: evidenceResult.evidence,
                reviewText: generationResult,
                updatedAt: Date()
            ),
            updatedAt: Date()
        )
        return ProjectReviewTaskTurnResult(
            snapshot: finishedSnapshot,
            reviewText: generationResult,
            systemMessages: systemMessages
        )
    }

    private func fetchUncommittedChanges() async -> ProjectUncommittedChangesContext {
        do {
            return try await projectContextService.fetchUncommittedChanges(
                serverURL: projectChangesEndpointURL
            )
        } catch {
            return ProjectUncommittedChangesContext(
                files: [],
                diff: "",
                diagnosticMessage: "Не удалось получить diff и изменённые файлы через MCP: \(error.localizedDescription)"
            )
        }
    }

    private func collectEvidence(
        changedFiles: [String],
        diff: String,
        strategy: ChunkingStrategyType
    ) async -> ProjectReviewRAGEvidenceResult {
        guard let ragUseCaseFacade else {
            AppLogger.shared.warning(
                "RAG не настроен для review-task, evidence не будет собран.",
                category: Self.ragLogCategory
            )
            return .notConfigured
        }
        do {
            try await ensureRAGIndexIsReady(ragUseCaseFacade, strategy: strategy)
            let query = buildRAGQuery(changedFiles: changedFiles, diff: diff)
            let results = try await ragUseCaseFacade.search(query: query, topK: 4)
            let evidence = results.map { result in
                ProjectReviewEvidence(
                    source: result.chunk.source,
                    section: result.chunk.section,
                    content: result.chunk.content
                )
            }
            if evidence.isEmpty {
                AppLogger.shared.info(
                    "RAG не нашёл релевантных фрагментов для review-task. query=\(queryPreview(query))",
                    category: Self.ragLogCategory
                )
                return .empty
            }
            AppLogger.shared.info(
                "RAG вернул \(evidence.count) фрагментов для review-task. query=\(queryPreview(query))",
                category: Self.ragLogCategory
            )
            return .found(evidence)
        } catch {
            AppLogger.shared.error(
                "RAG упал при сборе evidence для review-task: \(error.localizedDescription)",
                category: Self.ragLogCategory
            )
            return .failed(reason: error.localizedDescription)
        }
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

    private func generateReview(
        focus: String?,
        changes: ProjectUncommittedChangesContext,
        evidence: [ProjectReviewEvidence],
        settings: LLMSettings
    ) async throws -> String {
        let request = LLMRequest(
            systemPrompt: makeSystemPrompt(
                focus: focus,
                changes: changes,
                evidence: evidence
            ),
            shortTermMessages: [],
            workingMemory: [],
            longTermMemory: [],
            settings: settings
        )
        let response = try await llmClient.send(request: request)
        let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty {
            return "Ревью не удалось сгенерировать."
        }
        return content
    }

    private func generateReviewResult(
        focus: String?,
        changes: ProjectUncommittedChangesContext,
        evidence: [ProjectReviewEvidence],
        ragState: ProjectReviewRAGEvidenceResult,
        settings: LLMSettings
    ) async -> String {
        do {
            return try await generateReview(
                focus: focus,
                changes: changes,
                evidence: evidence,
                settings: settings
            )
        } catch {
            AppLogger.shared.error(
                "LLM упал при генерации ревью для review-task: \(error.localizedDescription)",
                category: Self.llmLogCategory
            )
            return buildFallbackReview(
                focus: focus,
                changes: changes,
                evidence: evidence,
                ragState: ragState
            )
        }
    }

    private func buildFallbackReview(
        focus: String?,
        changes: ProjectUncommittedChangesContext,
        evidence: [ProjectReviewEvidence],
        ragState: ProjectReviewRAGEvidenceResult
    ) -> String {
        var lines: [String] = []

        lines.append("Локальный разбор изменений проекта LightNeiroClient:")

        if let focus, !focus.isEmpty {
            lines.append("Фокус ревью: \(focus).")
        }

        if !changes.files.isEmpty {
            lines.append("Изменённые файлы:")
            for file in changes.files.prefix(12) {
                lines.append("- \(file)")
            }
            if changes.files.count > 12 {
                lines.append("- ... и ещё \(changes.files.count - 12) файлов")
            }
        } else {
            lines.append("Изменённые файлы не определены.")
        }

        if !changes.diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Diff получен и учтён в review-task.")
        }

        if !evidence.isEmpty {
            lines.append("RAG-контекст:")
            for item in evidence.prefix(3) {
                let section = item.section?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let section, !section.isEmpty {
                    lines.append("- \(item.source) — \(section)")
                } else {
                    lines.append("- \(item.source)")
                }
            }
        } else {
            lines.append(ragState.fallbackSummary)
        }

        lines.append("Критические замечания: требуется ручная проверка сгенерированного диффа.")
        lines.append("Риски: автоматическая генерация ревью была недоступна, поэтому возможны упущения в деталях.")
        lines.append("Замечания: проверьте связанные тесты, миграции и места использования изменённых API.")

        lines.append("Краткий итог: локальное ревью сформировано без ответа LLM.")
        return lines.joined(separator: "\n")
    }

    private func makeSystemPrompt(
        focus: String?,
        changes: ProjectUncommittedChangesContext,
        evidence: [ProjectReviewEvidence]
    ) -> String {
        var blocks: [String] = [
            "Ты senior code reviewer проекта LightNeiroClient.",
            "Отвечай на русском языке, кратко, по делу и без markdown-шума.",
            "Сначала перечисли наиболее важные проблемы, затем риски и короткие рекомендации.",
            "Если критичных проблем нет, явно скажи об этом.",
            "Опирайся только на UNCOMMITTED_CHANGES и RAG_EVIDENCE."
        ]

        if let focus, !focus.isEmpty {
            blocks.append("Фокус ревью: \(focus)")
        }

        blocks.append(makeFilesBlock(changes.files))
        blocks.append(makeDiffBlock(changes.diff))
        blocks.append(makeEvidenceBlock(evidence))
        blocks.append("""
        Формат ответа:
        - Критические замечания
        - Риски
        - Замечания
        - Краткий итог
        """)
        return blocks.joined(separator: "\n\n")
    }

    private func makeFilesBlock(_ files: [String]) -> String {
        guard !files.isEmpty else {
            return "UNCOMMITTED_FILES:\n- no files"
        }

        var lines: [String] = ["UNCOMMITTED_FILES (\(files.count)):"]
        for file in files.prefix(80) {
            lines.append("- \(file)")
        }
        if files.count > 80 {
            lines.append("- ... and \(files.count - 80) more")
        }
        return lines.joined(separator: "\n")
    }

    private func makeDiffBlock(_ diff: String) -> String {
        let normalized = diff.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            return "UNCOMMITTED_DIFF:\n- empty"
        }
        return "UNCOMMITTED_DIFF:\n\(normalized)"
    }

    private func makeEvidenceBlock(_ evidence: [ProjectReviewEvidence]) -> String {
        guard !evidence.isEmpty else {
            return "RAG_EVIDENCE:\n- evidence unavailable"
        }

        var lines: [String] = ["RAG_EVIDENCE:"]
        for (index, item) in evidence.enumerated() {
            let section = item.section?.trimmingCharacters(in: .whitespacesAndNewlines)
            let sectionText = (section?.isEmpty == false) ? (section ?? "null") : "null"
            let text = item.content
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("[\(index + 1)] source=\(item.source) section=\(sectionText) text=\(text)")
        }
        return lines.joined(separator: "\n")
    }

    private func buildRAGQuery(changedFiles: [String], diff: String) -> String {
        let fileQuery = changedFiles.prefix(12).joined(separator: " ")
        let diffLines = diff
            .split(separator: "\n", omittingEmptySubsequences: true)
            .prefix(12)
            .map(String.init)
            .joined(separator: " ")
        let combined = "\(fileQuery) \(diffLines)".trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.isEmpty ? "code review best practices" : combined
    }

    private func stateChangeMessage(for state: ProjectReviewTaskState) -> String {
        let ordered: [ProjectReviewTaskState] = [
            .idle,
            .collectingChanges,
            .workingWithRAG,
            .analyzingChanges
        ]

        var lines: [String] = ["Состояния review task-агента (текущее отмечено [x]):"]
        for item in ordered {
            let marker = item == state ? "[x]" : "[ ]"
            lines.append("\(marker) \(item.title)")
        }
        if case let .failed(reason) = state {
            lines.append("[x] Ошибка: \(reason)")
        }
        return lines.joined(separator: "\n")
    }

    private func queryPreview(_ query: String) -> String {
        let normalized = query.replacingOccurrences(of: "\n", with: " ")
        if normalized.count <= 120 {
            return normalized
        }
        let prefix = normalized.prefix(117)
        return "\(prefix)..."
    }
}

private actor ProjectReviewRAGIndexState {
    private var readyStrategies: Set<ChunkingStrategyType>

    init(initialStrategy: ChunkingStrategyType?) {
        if let initialStrategy {
            self.readyStrategies = [initialStrategy]
        } else {
            self.readyStrategies = []
        }
    }

    func isReady(for strategy: ChunkingStrategyType) -> Bool {
        readyStrategies.contains(strategy)
    }

    func markReady(for strategy: ChunkingStrategyType) {
        readyStrategies.insert(strategy)
    }
}

private enum ProjectReviewRAGEvidenceResult: Sendable {
    case notConfigured
    case empty
    case failed(reason: String)
    case found([ProjectReviewEvidence])

    var evidence: [ProjectReviewEvidence] {
        switch self {
        case let .found(evidence):
            return evidence
        case .notConfigured, .empty, .failed:
            return []
        }
    }

    var fallbackSummary: String {
        switch self {
        case .notConfigured:
            return "RAG-контекст не настроен."
        case .empty:
            return "RAG-контекст не нашёл релевантных фрагментов."
        case .failed:
            return "RAG-контекст временно недоступен."
        case .found:
            return "RAG-контекст недоступен или пуст."
        }
    }
}

import Foundation

final class ProjectHelpUseCase: ProjectHelpUseCaseProtocol {
    private let settingsRepository: SettingsRepositoryProtocol
    private let llmClient: LLMClientProtocol
    private let ragUseCaseFacade: RAGUseCaseFacadeProtocol?
    private let projectContextService: ProjectGitBranchServiceProtocol
    private let projectBranchEndpointURL: URL
    private let ragDocumentsProvider: @Sendable () -> [URL]
    private let ragIndexState: ProjectHelpRAGIndexState

    init(
        settingsRepository: SettingsRepositoryProtocol,
        llmClient: LLMClientProtocol,
        ragUseCaseFacade: RAGUseCaseFacadeProtocol?,
        projectContextService: ProjectGitBranchServiceProtocol,
        projectBranchEndpointURL: URL = URL(string: "stdio://project")!,
        ragDocumentsProvider: @escaping @Sendable () -> [URL] = { [] },
        initialIndexedRAGStrategy: ChunkingStrategyType? = nil
    ) {
        self.settingsRepository = settingsRepository
        self.llmClient = llmClient
        self.ragUseCaseFacade = ragUseCaseFacade
        self.projectContextService = projectContextService
        self.projectBranchEndpointURL = projectBranchEndpointURL
        self.ragDocumentsProvider = ragDocumentsProvider
        self.ragIndexState = ProjectHelpRAGIndexState(initialStrategy: initialIndexedRAGStrategy)
    }

    func execute(question: String?) async -> String {
        let normalizedQuestion = question?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let searchQuery = normalizedQuestion.isEmpty
            ? "структура проекта LightNeiroClient README Doc"
            : normalizedQuestion
        let settings = (try? await settingsRepository.fetchSettings()) ?? .default

        async let branchTask = fetchProjectBranch()
        async let evidenceTask = collectEvidence(
            for: searchQuery,
            strategy: settings.ragChunkingStrategy
        )

        let branch = await branchTask
        let evidence = await evidenceTask

        if evidence.isEmpty {
            return buildFallbackAnswer(
                question: normalizedQuestion,
                branch: branch,
                evidence: []
            )
        }

        do {
            let request = LLMRequest(
                systemPrompt: makeSystemPrompt(
                    question: normalizedQuestion,
                    branch: branch,
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
                return buildFallbackAnswer(
                    question: normalizedQuestion,
                    branch: branch,
                    evidence: evidence
                )
            }
            return content
        } catch {
            return buildFallbackAnswer(
                question: normalizedQuestion,
                branch: branch,
                evidence: evidence
            )
        }
    }

    private func fetchProjectBranch() async -> String? {
        do {
            let branch = try await projectContextService.fetchCurrentGitBranch(
                serverURL: projectBranchEndpointURL
            )
            let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }

    private func collectEvidence(for query: String, strategy: ChunkingStrategyType) async -> [ProjectHelpEvidence] {
        guard let ragUseCaseFacade else { return [] }
        do {
            try await ensureRAGIndexIsReady(ragUseCaseFacade, strategy: strategy)
            let results = try await ragUseCaseFacade.search(query: query, topK: 4)
            return results.map { result in
                ProjectHelpEvidence(
                    source: result.chunk.source,
                    section: result.chunk.section,
                    text: result.chunk.content
                )
            }
        } catch {
            return []
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

    private func makeSystemPrompt(
        question: String,
        branch: String?,
        evidence: [ProjectHelpEvidence]
    ) -> String {
        var blocks: [String] = [
            "Ты ассистент разработчика проекта LightNeiroClient.",
            "Отвечай на русском языке, кратко, по делу и без markdown-шума.",
            "Используй только сведения из PROJECT_CONTEXT и RAG_EVIDENCE.",
            "Если в источниках нет подтверждения, честно скажи об этом.",
            "Если вопрос касается структуры проекта, опирайся на README.md и материалы из LightNeiroClient/Doc."
        ]

        let branchText = branch ?? "не удалось определить"
        blocks.append(
            "PROJECT_CONTEXT:\n- git branch: \(branchText)\n- repository: LightNeiroClient\n- docs: README.md, LightNeiroClient/Doc"
        )

        if question.isEmpty {
            blocks.append("Вопрос пользователя: дай обзор структуры проекта и ключевых команд.")
        } else {
            blocks.append("Вопрос пользователя: \(question)")
        }

        blocks.append(makeEvidenceBlock(evidence))
        blocks.append("В конце ответа при необходимости укажи текущую git-ветку и краткий список источников.")
        return blocks.joined(separator: "\n\n")
    }

    private func makeEvidenceBlock(_ evidence: [ProjectHelpEvidence]) -> String {
        guard !evidence.isEmpty else {
            return "RAG_EVIDENCE:\n- evidence unavailable"
        }

        var lines: [String] = ["RAG_EVIDENCE:"]
        for (index, item) in evidence.enumerated() {
            let section = item.section?.trimmingCharacters(in: .whitespacesAndNewlines)
            let sectionText = (section?.isEmpty == false) ? (section ?? "null") : "null"
            let text = item.text
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("[\(index + 1)] source=\(item.source) section=\(sectionText) text=\(text)")
        }
        return lines.joined(separator: "\n")
    }

    private func buildFallbackAnswer(
        question: String,
        branch: String?,
        evidence: [ProjectHelpEvidence]
    ) -> String {
        var lines: [String] = []

        if question.isEmpty {
            lines.append("Краткий обзор проекта LightNeiroClient:")
        } else {
            lines.append("Ответ по проекту LightNeiroClient:")
        }

        if let branch, !branch.isEmpty {
            lines.append("Текущая git-ветка: \(branch).")
        } else {
            lines.append("Текущая git-ветка: не удалось определить.")
        }

        lines.append("Структура проекта: App, Domain, Data, Presentation и LightNeiroClientTests.")
        lines.append("Документация: README.md и материалы из LightNeiroClient/Doc.")

        if !question.isEmpty {
            lines.append("Вопрос: \(question)")
        }

        if !evidence.isEmpty {
            lines.append("Найденные источники:")
            for item in evidence.prefix(3) {
                let section = item.section?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let section, !section.isEmpty {
                    lines.append("- \(item.source) — \(section)")
                } else {
                    lines.append("- \(item.source)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }
}

private actor ProjectHelpRAGIndexState {
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

private struct ProjectHelpEvidence {
    let source: String
    let section: String?
    let text: String
}

import Foundation

struct HackerNewsLLMSummaryService: HackerNewsLLMSummaryServiceProtocol {
    private let llmClient: LLMClientProtocol
    private let settingsRepository: SettingsRepositoryProtocol

    init(
        llmClient: LLMClientProtocol,
        settingsRepository: SettingsRepositoryProtocol
    ) {
        self.llmClient = llmClient
        self.settingsRepository = settingsRepository
    }

    func summarize(
        sessionID: UUID,
        recentStories: [HackerNewsTaskAgentStoryDigest]
    ) async throws -> String {
        guard !recentStories.isEmpty else {
            return "Нет статей для сводки."
        }

        let settings = try await settingsRepository.fetchSettings(sessionID: sessionID)
        let request = LLMRequest(
            systemPrompt: "Ты помощник, который кратко суммирует новости Hacker News на русском языке. Дай 2-3 предложения без markdown.",
            shortTermMessages: [
                ChatMessage(
                    branchID: UUID(),
                    role: .user,
                    content: makePrompt(stories: recentStories)
                )
            ],
            workingMemory: [],
            longTermMemory: [],
            settings: settings
        )

        let response = try await llmClient.send(request: request)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makePrompt(stories: [HackerNewsTaskAgentStoryDigest]) -> String {
        let lines = stories.map { digest in
            let author = digest.author?.isEmpty == false ? digest.author! : "unknown"
            let url = digest.url?.isEmpty == false ? digest.url! : "no-url"
            return "#\(digest.requestNumber) | \(digest.title) | author=\(author) | url=\(url)"
        }
        return "Суммируй эти статьи:\n\n\(lines.joined(separator: "\n"))"
    }
}

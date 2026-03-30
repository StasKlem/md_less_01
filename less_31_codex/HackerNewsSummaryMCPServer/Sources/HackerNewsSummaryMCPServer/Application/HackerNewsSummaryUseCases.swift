import Foundation

protocol SummarizeHackerNewsStoriesUseCaseProtocol: Sendable {
    func execute(stories: [HackerNewsStoryForSummary], language: String) async throws -> String
}

struct SummarizeHackerNewsStoriesUseCase: SummarizeHackerNewsStoriesUseCaseProtocol {
    private let repository: HackerNewsSummaryRepository

    init(repository: HackerNewsSummaryRepository) {
        self.repository = repository
    }

    func execute(stories: [HackerNewsStoryForSummary], language: String) async throws -> String {
        guard !stories.isEmpty else {
            throw HackerNewsSummaryToolError.invalidArguments("Argument 'stories' must contain at least one story.")
        }
        return try await repository.summarize(stories: stories, language: language)
    }
}

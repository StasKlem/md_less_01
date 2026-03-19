import Foundation

protocol TranslateHackerNewsStoryUseCaseProtocol: Sendable {
    func execute(story: HackerNewsStoryForTranslation, language: String) async throws -> String
}

struct TranslateHackerNewsStoryUseCase: TranslateHackerNewsStoryUseCaseProtocol {
    private let repository: HackerNewsTranslateRepository

    init(repository: HackerNewsTranslateRepository) {
        self.repository = repository
    }

    func execute(story: HackerNewsStoryForTranslation, language: String) async throws -> String {
        try await repository.translate(story: story, language: language)
    }
}

import Foundation

protocol GetRandomStoryUseCaseProtocol: Sendable {
    func execute() async throws -> HackerNewsStory
}

struct GetRandomStoryUseCase: GetRandomStoryUseCaseProtocol {
    private let repository: HackerNewsRepository

    init(repository: HackerNewsRepository) {
        self.repository = repository
    }

    func execute() async throws -> HackerNewsStory {
        try await repository.randomStory()
    }
}

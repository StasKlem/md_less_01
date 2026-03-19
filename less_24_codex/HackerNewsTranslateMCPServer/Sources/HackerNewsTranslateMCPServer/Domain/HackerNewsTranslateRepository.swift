import Foundation

protocol HackerNewsTranslateRepository: Sendable {
    func translate(story: HackerNewsStoryForTranslation, language: String) async throws -> String
}

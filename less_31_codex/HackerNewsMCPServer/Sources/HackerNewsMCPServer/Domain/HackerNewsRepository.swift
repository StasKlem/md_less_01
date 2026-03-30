import Foundation

protocol HackerNewsRepository: Sendable {
    func randomStory() async throws -> HackerNewsStory
}

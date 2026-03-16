import Foundation

protocol HackerNewsSummaryRepository: Sendable {
    func summarize(stories: [HackerNewsStoryForSummary], language: String) async throws -> String
}

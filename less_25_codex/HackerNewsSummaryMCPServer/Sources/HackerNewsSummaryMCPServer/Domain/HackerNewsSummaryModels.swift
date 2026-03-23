import Foundation

struct HackerNewsStoryForSummary: Sendable, Equatable {
    let id: Int?
    let title: String
    let author: String?
    let score: Int?
    let publishedAtUTC: String?
    let url: String?
    let rawText: String
}

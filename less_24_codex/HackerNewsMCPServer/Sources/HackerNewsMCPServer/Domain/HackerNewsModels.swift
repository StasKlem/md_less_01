import Foundation

struct HackerNewsStory: Sendable {
    let id: Int
    let title: String
    let author: String?
    let url: URL?
    let score: Int?
    let timestamp: Date?
}

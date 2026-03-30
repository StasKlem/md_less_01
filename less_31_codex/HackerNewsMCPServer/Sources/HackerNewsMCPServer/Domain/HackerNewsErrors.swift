import Foundation

enum HackerNewsToolError: LocalizedError, Sendable, Equatable {
    case invalidArguments(String)
    case noStoriesFound
    case upstreamFailure(String)
    case decodingFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return message
        case .noStoriesFound:
            return "Could not find a valid story in Hacker News top stories."
        case .upstreamFailure(let message):
            return "Hacker News request failed: \(message)"
        case .decodingFailure(let message):
            return "Hacker News response parsing failed: \(message)"
        }
    }
}

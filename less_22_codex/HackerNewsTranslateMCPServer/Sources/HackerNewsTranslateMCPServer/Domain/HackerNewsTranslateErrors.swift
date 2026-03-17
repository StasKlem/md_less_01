import Foundation

enum HackerNewsTranslateToolError: LocalizedError, Sendable, Equatable {
    case invalidArguments(String)
    case llmFailure(String)
    case parsingFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return message
        case .llmFailure(let message):
            return "LLM translation failed: \(message)"
        case .parsingFailure(let message):
            return "Could not parse story: \(message)"
        }
    }
}

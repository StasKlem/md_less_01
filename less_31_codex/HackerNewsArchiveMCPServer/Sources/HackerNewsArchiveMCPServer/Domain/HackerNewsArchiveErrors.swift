import Foundation

enum HackerNewsArchiveToolError: LocalizedError, Sendable, Equatable {
    case invalidArguments(String)
    case fileIO(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return message
        case .fileIO(let message):
            return "File storage failed: \(message)"
        }
    }
}

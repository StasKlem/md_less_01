import Foundation

enum ProjectRepositoryError: Error, LocalizedError, Sendable {
    case gitCommandFailed(String)
    case invalidRepositoryRoot

    var errorDescription: String? {
        switch self {
        case .gitCommandFailed(let message):
            return message
        case .invalidRepositoryRoot:
            return "Project repository root is invalid."
        }
    }
}

enum ProjectWorkspaceError: Error, LocalizedError, Sendable {
    case invalidRelativePath(String)
    case invalidSearchQuery
    case fileOperationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidRelativePath(let path):
            return "Invalid project file path: \(path)"
        case .invalidSearchQuery:
            return "Search query must not be empty."
        case .fileOperationFailed(let message):
            return message
        }
    }
}

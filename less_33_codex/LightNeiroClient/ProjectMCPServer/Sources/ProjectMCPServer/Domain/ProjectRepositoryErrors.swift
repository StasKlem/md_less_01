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

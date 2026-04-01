import Foundation

protocol ProjectRepositoryProtocol: Sendable {
    func currentGitBranch() throws -> String
    func listProjectFiles() throws -> [ProjectFile]
    func uncommittedChanges() throws -> ProjectUncommittedChanges
}

import Foundation

protocol ProjectRepositoryProtocol: Sendable {
    func currentGitBranch() throws -> String
    func listProjectFiles() throws -> [ProjectFile]
    func uncommittedChanges() throws -> ProjectUncommittedChanges
}

protocol ProjectWorkspaceRepositoryProtocol: Sendable {
    func readFile(relativePath: String) throws -> ProjectFileReadResult
    func searchFiles(query: String, files: [ProjectFile]) throws -> ProjectFileSearchResult
    func writeFile(relativePath: String, contents: String) throws -> ProjectFileWriteResult
}

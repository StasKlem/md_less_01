import Foundation

struct GitProjectRepository: ProjectRepositoryProtocol {
    let rootDirectory: URL

    func currentGitBranch() throws -> String {
        if let branch = runGit(arguments: ["branch", "--show-current"]),
           !branch.isEmpty
        {
            return branch
        }

        if let sha = runGit(arguments: ["rev-parse", "--short", "HEAD"]),
           !sha.isEmpty
        {
            return "detached HEAD (\(sha))"
        }

        throw ProjectRepositoryError.gitCommandFailed("Failed to read current git branch.")
    }

    func listProjectFiles() throws -> [ProjectFile] {
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else {
            throw ProjectRepositoryError.invalidRepositoryRoot
        }

        guard let output = runGit(arguments: ["ls-files", "--cached", "--others", "--exclude-standard"]) else {
            throw ProjectRepositoryError.gitCommandFailed("Failed to list project files.")
        }

        return output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { ProjectFile(relativePath: $0) }
    }

    private func runGit(arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = rootDirectory

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

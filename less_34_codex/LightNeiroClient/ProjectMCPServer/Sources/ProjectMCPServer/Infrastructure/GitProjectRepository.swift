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

    func uncommittedChanges() throws -> ProjectUncommittedChanges {
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else {
            throw ProjectRepositoryError.invalidRepositoryRoot
        }

        let statusOutput = runGit(arguments: ["status", "--porcelain=v1"])
        let files = parseStatusFiles(from: statusOutput ?? "")
        let stagedDiff = runGitAllowingDiffExit(arguments: ["diff", "--cached", "--no-ext-diff", "--unified=3"]) ?? ""
        let workingTreeDiff = runGitAllowingDiffExit(arguments: ["diff", "--no-ext-diff", "--unified=3"]) ?? ""
        let untrackedDiff = buildUntrackedFilesDiff(from: statusOutput ?? "")

        let diffParts = [stagedDiff, workingTreeDiff, untrackedDiff]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return ProjectUncommittedChanges(
            files: files,
            diff: diffParts.joined(separator: "\n\n")
        )
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

    private func runGitAllowingDiffExit(arguments: [String]) -> String? {
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
        guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseStatusFiles(from statusOutput: String) -> [ProjectFile] {
        let lines = statusOutput
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)

        var files: [String] = []
        for line in lines {
            guard line.count >= 4 else { continue }
            let pathPart = String(line.dropFirst(3))
            if line.hasPrefix("?? ") {
                files.append(pathPart)
            } else if let renamedRange = pathPart.range(of: " -> ") {
                files.append(String(pathPart[renamedRange.upperBound...]))
            } else {
                files.append(pathPart)
            }
        }

        return Array(Set(files))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { ProjectFile(relativePath: $0) }
    }

    private func buildUntrackedFilesDiff(from statusOutput: String) -> String {
        let untrackedFiles = statusOutput
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { $0.hasPrefix("?? ") }
            .map { String($0.dropFirst(3)) }

        guard !untrackedFiles.isEmpty else {
            return ""
        }

        var blocks: [String] = []
        for file in untrackedFiles {
            let output = runGitAllowingDiffExit(arguments: ["diff", "--no-ext-diff", "--unified=3", "--no-index", "/dev/null", file]) ?? ""
            let normalized = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                blocks.append(normalized)
            }
        }
        return blocks.joined(separator: "\n\n")
    }
}

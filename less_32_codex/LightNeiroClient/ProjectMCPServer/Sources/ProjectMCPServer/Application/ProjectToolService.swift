import Foundation
import MCP

struct ProjectToolService: Sendable {
    private let getCurrentGitBranchUseCase: GetCurrentGitBranchUseCaseProtocol
    private let listProjectFilesUseCase: ListProjectFilesUseCaseProtocol
    private let getUncommittedChangesUseCase: GetUncommittedChangesUseCaseProtocol
    private let logger: StderrLogger?

    init(
        getCurrentGitBranchUseCase: GetCurrentGitBranchUseCaseProtocol,
        listProjectFilesUseCase: ListProjectFilesUseCaseProtocol,
        getUncommittedChangesUseCase: GetUncommittedChangesUseCaseProtocol,
        logger: StderrLogger? = nil
    ) {
        self.getCurrentGitBranchUseCase = getCurrentGitBranchUseCase
        self.listProjectFilesUseCase = listProjectFilesUseCase
        self.getUncommittedChangesUseCase = getUncommittedChangesUseCase
        self.logger = logger
    }

    func callTool(name: String, arguments: [String: Value]?) async -> CallTool.Result {
        logger?.debug("Tool call received: \(name)")

        do {
            switch name {
            case ProjectToolCatalog.currentGitBranchToolName:
                let result = try handleCurrentGitBranch(arguments: arguments)
                logger?.info("Tool call succeeded: \(name)")
                return result
            case ProjectToolCatalog.listProjectFilesToolName:
                let result = try handleListProjectFiles(arguments: arguments)
                logger?.info("Tool call succeeded: \(name)")
                return result
            case ProjectToolCatalog.uncommittedChangesToolName:
                let result = try handleUncommittedChanges(arguments: arguments)
                logger?.info("Tool call succeeded: \(name)")
                return result
            default:
                logger?.warn("Unknown tool requested: \(name)")
                return Self.errorResult("Unknown tool: \(name)")
            }
        } catch {
            logger?.error("Tool call failed: \(name). Error: \(error.localizedDescription)")
            return Self.errorResult(error.localizedDescription)
        }
    }

    private func handleCurrentGitBranch(arguments: [String: Value]?) throws -> CallTool.Result {
        if let arguments, !arguments.isEmpty {
            throw ProjectToolError.invalidArguments(
                "Tool \(ProjectToolCatalog.currentGitBranchToolName) does not accept arguments."
            )
        }

        let branch = try getCurrentGitBranchUseCase.execute()
        return .init(content: [.text(branch)], isError: false)
    }

    private func handleListProjectFiles(arguments: [String: Value]?) throws -> CallTool.Result {
        if let arguments, !arguments.isEmpty {
            throw ProjectToolError.invalidArguments(
                "Tool \(ProjectToolCatalog.listProjectFilesToolName) does not accept arguments."
            )
        }

        let files = try listProjectFilesUseCase.execute()
        return .init(content: [.text(ProjectFilesFormatter.format(files))], isError: false)
    }

    private func handleUncommittedChanges(arguments: [String: Value]?) throws -> CallTool.Result {
        if let arguments, !arguments.isEmpty {
            throw ProjectToolError.invalidArguments(
                "Tool \(ProjectToolCatalog.uncommittedChangesToolName) does not accept arguments."
            )
        }

        let changes = try getUncommittedChangesUseCase.execute()
        let payload = ProjectUncommittedChangesFormatter.format(changes)
        return .init(content: [.text(payload)], isError: false)
    }

    private static func errorResult(_ message: String) -> CallTool.Result {
        .init(content: [.text(message)], isError: true)
    }
}

private enum ProjectFilesFormatter {
    static func format(_ files: [ProjectFile]) -> String {
        guard !files.isEmpty else {
            return "No project files found."
        }

        var lines: [String] = ["Project files (\(files.count)):"]
        for file in files {
            lines.append(file.relativePath)
        }
        return lines.joined(separator: "\n")
    }
}

private enum ProjectUncommittedChangesFormatter {
    static func format(_ changes: ProjectUncommittedChanges) -> String {
        let payload = ProjectUncommittedChangesPayload(
            files: changes.files.map(\.relativePath),
            diff: changes.diff
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload),
              let text = String(data: data, encoding: .utf8)
        else {
            return "{\"files\":[],\"diff\":\"\"}"
        }
        return text
    }
}

private struct ProjectUncommittedChangesPayload: Codable, Sendable {
    let files: [String]
    let diff: String
}

private enum ProjectToolError: Error, LocalizedError, Sendable {
    case invalidArguments(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return message
        }
    }
}

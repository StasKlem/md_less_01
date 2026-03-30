import Foundation
import MCP

struct ProjectToolService: Sendable {
    private let getCurrentGitBranchUseCase: GetCurrentGitBranchUseCaseProtocol
    private let listProjectFilesUseCase: ListProjectFilesUseCaseProtocol
    private let logger: StderrLogger?

    init(
        getCurrentGitBranchUseCase: GetCurrentGitBranchUseCaseProtocol,
        listProjectFilesUseCase: ListProjectFilesUseCaseProtocol,
        logger: StderrLogger? = nil
    ) {
        self.getCurrentGitBranchUseCase = getCurrentGitBranchUseCase
        self.listProjectFilesUseCase = listProjectFilesUseCase
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

private enum ProjectToolError: Error, LocalizedError, Sendable {
    case invalidArguments(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return message
        }
    }
}

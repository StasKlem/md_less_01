import Foundation
import MCP

struct ProjectToolService: Sendable {
    private let getCurrentGitBranchUseCase: GetCurrentGitBranchUseCaseProtocol
    private let listProjectFilesUseCase: ListProjectFilesUseCaseProtocol
    private let getUncommittedChangesUseCase: GetUncommittedChangesUseCaseProtocol
    private let readProjectFileUseCase: ReadProjectFileUseCaseProtocol
    private let searchProjectFilesUseCase: SearchProjectFilesUseCaseProtocol
    private let writeProjectFileUseCase: WriteProjectFileUseCaseProtocol
    private let logger: StderrLogger?

    init(
        getCurrentGitBranchUseCase: GetCurrentGitBranchUseCaseProtocol,
        listProjectFilesUseCase: ListProjectFilesUseCaseProtocol,
        getUncommittedChangesUseCase: GetUncommittedChangesUseCaseProtocol,
        readProjectFileUseCase: ReadProjectFileUseCaseProtocol,
        searchProjectFilesUseCase: SearchProjectFilesUseCaseProtocol,
        writeProjectFileUseCase: WriteProjectFileUseCaseProtocol,
        logger: StderrLogger? = nil
    ) {
        self.getCurrentGitBranchUseCase = getCurrentGitBranchUseCase
        self.listProjectFilesUseCase = listProjectFilesUseCase
        self.getUncommittedChangesUseCase = getUncommittedChangesUseCase
        self.readProjectFileUseCase = readProjectFileUseCase
        self.searchProjectFilesUseCase = searchProjectFilesUseCase
        self.writeProjectFileUseCase = writeProjectFileUseCase
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
            case ProjectToolCatalog.readProjectFileToolName:
                let result = try handleReadProjectFile(arguments: arguments)
                logger?.info("Tool call succeeded: \(name)")
                return result
            case ProjectToolCatalog.searchProjectFilesToolName:
                let result = try handleSearchProjectFiles(arguments: arguments)
                logger?.info("Tool call succeeded: \(name)")
                return result
            case ProjectToolCatalog.writeProjectFileToolName:
                let result = try handleWriteProjectFile(arguments: arguments)
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

    private func handleReadProjectFile(arguments: [String: Value]?) throws -> CallTool.Result {
        let relativePath = try extractRequiredString(
            name: "relativePath",
            from: arguments,
            toolName: ProjectToolCatalog.readProjectFileToolName
        )

        let result = try readProjectFileUseCase.execute(relativePath: relativePath)
        return .init(content: [.text(ProjectFileReadFormatter.format(result))], isError: false)
    }

    private func handleSearchProjectFiles(arguments: [String: Value]?) throws -> CallTool.Result {
        let query = try extractRequiredString(
            name: "query",
            from: arguments,
            toolName: ProjectToolCatalog.searchProjectFilesToolName
        )

        let result = try searchProjectFilesUseCase.execute(query: query)
        return .init(content: [.text(ProjectFileSearchFormatter.format(result))], isError: false)
    }

    private func handleWriteProjectFile(arguments: [String: Value]?) throws -> CallTool.Result {
        let relativePath = try extractRequiredString(
            name: "relativePath",
            from: arguments,
            toolName: ProjectToolCatalog.writeProjectFileToolName
        )
        let content = try extractRequiredString(
            name: "content",
            from: arguments,
            toolName: ProjectToolCatalog.writeProjectFileToolName
        )

        let result = try writeProjectFileUseCase.execute(relativePath: relativePath, contents: content)
        return .init(content: [.text(ProjectFileWriteFormatter.format(result))], isError: false)
    }

    private func extractRequiredString(
        name: String,
        from arguments: [String: Value]?,
        toolName: String
    ) throws -> String {
        guard let arguments else {
            throw ProjectToolError.invalidArguments("Tool \(toolName) requires argument \(name).")
        }

        guard let value = arguments[name] else {
            throw ProjectToolError.invalidArguments("Tool \(toolName) requires argument \(name).")
        }

        switch value {
        case .string(let string):
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ProjectToolError.invalidArguments("Tool \(toolName) requires argument \(name).")
            }
            return trimmed
        default:
            throw ProjectToolError.invalidArguments("Tool \(toolName) requires string argument \(name).")
        }
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
        return encode(payload)
    }
}

private enum ProjectFileReadFormatter {
    static func format(_ result: ProjectFileReadResult) -> String {
        let payload = ProjectFileReadPayload(
            relativePath: result.relativePath,
            lineCount: result.lineCount,
            content: result.content
        )
        return encode(payload)
    }
}

private enum ProjectFileSearchFormatter {
    static func format(_ result: ProjectFileSearchResult) -> String {
        let payload = ProjectFileSearchPayload(
            query: result.query,
            isTruncated: result.isTruncated,
            matches: result.matches
        )
        return encode(payload)
    }
}

private enum ProjectFileWriteFormatter {
    static func format(_ result: ProjectFileWriteResult) -> String {
        let payload = ProjectFileWritePayload(
            relativePath: result.relativePath,
            created: result.created,
            changed: result.changed,
            diff: result.diff
        )
        return encode(payload)
    }
}

private func encode<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(value),
          let text = String(data: data, encoding: .utf8)
    else {
        return "{}"
    }
    return text.replacingOccurrences(of: "\\/", with: "/")
}

private struct ProjectFileReadPayload: Codable, Sendable {
    let relativePath: String
    let lineCount: Int
    let content: String
}

private struct ProjectFileSearchPayload: Codable, Sendable {
    let query: String
    let isTruncated: Bool
    let matches: [ProjectFileSearchMatch]
}

private struct ProjectFileWritePayload: Codable, Sendable {
    let relativePath: String
    let created: Bool
    let changed: Bool
    let diff: String
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

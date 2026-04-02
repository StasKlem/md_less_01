import Foundation
import MCP

struct HackerNewsArchiveToolService: Sendable {
    private let saveUseCase: SaveHackerNewsJSONUseCaseProtocol
    private let recentFilesUseCase: GetRecentHackerNewsFilesUseCaseProtocol
    private let logger: Logger?

    init(
        saveUseCase: SaveHackerNewsJSONUseCaseProtocol,
        recentFilesUseCase: GetRecentHackerNewsFilesUseCaseProtocol,
        logger: Logger? = nil
    ) {
        self.saveUseCase = saveUseCase
        self.recentFilesUseCase = recentFilesUseCase
        self.logger = logger
    }

    func callTool(name: String, arguments: [String: Value]?) async -> CallTool.Result {
        logger?.debug("Tool call received: \(name)")
        do {
            switch name {
            case HackerNewsArchiveToolCatalog.saveJSONToolName:
                let result = try handleSave(arguments: arguments)
                logger?.info("Tool call succeeded: \(name)")
                return result
            case HackerNewsArchiveToolCatalog.listLatestToolName:
                let result = try handleListLatest(arguments: arguments)
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

    private func handleSave(arguments: [String: Value]?) throws -> CallTool.Result {
        guard let json = arguments?["json"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !json.isEmpty
        else {
            throw HackerNewsArchiveToolError.invalidArguments("Argument 'json' is required.")
        }

        let archived = try saveUseCase.execute(json: json)
        let message = "Saved Hacker News JSON: \(archived.fileName)"
        return .init(content: [.text(message)], isError: false)
    }

    private func handleListLatest(arguments: [String: Value]?) throws -> CallTool.Result {
        if let arguments, !arguments.isEmpty {
            throw HackerNewsArchiveToolError.invalidArguments(
                "Tool hackernews_archive_get_latest_files does not accept arguments."
            )
        }

        let recentFiles = try recentFilesUseCase.execute(limit: 3)
        return .init(content: [.text(LatestFilesFormatter.format(recentFiles))], isError: false)
    }

    private static func errorResult(_ message: String) -> CallTool.Result {
        .init(content: [.text(message)], isError: true)
    }
}

private enum LatestFilesFormatter {
    static func format(_ files: [ArchivedHackerNewsFile]) -> String {
        guard !files.isEmpty else {
            return "No saved Hacker News JSON files found."
        }

        var lines: [String] = ["Latest saved Hacker News JSON files:"]
        for file in files {
            lines.append("---")
            lines.append("File: \(file.fileName)")
            lines.append(file.json)
        }
        return lines.joined(separator: "\n")
    }
}

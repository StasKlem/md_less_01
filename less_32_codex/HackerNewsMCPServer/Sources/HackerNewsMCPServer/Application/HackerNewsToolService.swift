import Foundation
import MCP

struct HackerNewsToolService: Sendable {
    private let randomStoryUseCase: GetRandomStoryUseCaseProtocol
    private let logger: Logger?

    init(
        randomStoryUseCase: GetRandomStoryUseCaseProtocol,
        logger: Logger? = nil
    ) {
        self.randomStoryUseCase = randomStoryUseCase
        self.logger = logger
    }

    func callTool(name: String, arguments: [String: Value]?) async -> CallTool.Result {
        logger?.debug("Tool call received: \(name)")
        do {
            switch name {
            case HackerNewsToolCatalog.randomStoryToolName:
                let result = try await handleRandomStory(arguments: arguments)
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

    private func handleRandomStory(arguments: [String: Value]?) async throws -> CallTool.Result {
        if let arguments, !arguments.isEmpty {
            throw HackerNewsToolError.invalidArguments(
                "Tool hackernews_get_random_story does not accept arguments."
            )
        }

        let story = try await randomStoryUseCase.execute()
        return .init(content: [.text(RandomStoryFormatter.format(story))], isError: false)
    }

    private static func errorResult(_ message: String) -> CallTool.Result {
        .init(content: [.text(message)], isError: true)
    }
}

private enum RandomStoryFormatter {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static func format(_ story: HackerNewsStory) -> String {
        var lines: [String] = [
            "Random Hacker News story:",
            "- Title: \(story.title)",
            "- ID: \(story.id)"
        ]

        if let author = story.author, !author.isEmpty {
            lines.append("- Author: \(author)")
        }

        if let score = story.score {
            lines.append("- Score: \(score)")
        }

        if let timestamp = story.timestamp {
            lines.append("- Time: \(dateFormatter.string(from: timestamp)) UTC")
        }

        if let url = story.url {
            lines.append("- URL: \(url.absoluteString)")
        } else {
            lines.append("- URL: (no external URL)")
        }

        return lines.joined(separator: "\n")
    }
}

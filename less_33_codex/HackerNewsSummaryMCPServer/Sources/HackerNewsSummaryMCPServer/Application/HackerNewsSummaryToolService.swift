import Foundation
import MCP

struct HackerNewsSummaryToolService: Sendable {
    private let summarizeUseCase: SummarizeHackerNewsStoriesUseCaseProtocol
    private let parser: HackerNewsStoryInputParser
    private let logger: Logger?

    init(
        summarizeUseCase: SummarizeHackerNewsStoriesUseCaseProtocol,
        parser: HackerNewsStoryInputParser = HackerNewsStoryInputParser(),
        logger: Logger? = nil
    ) {
        self.summarizeUseCase = summarizeUseCase
        self.parser = parser
        self.logger = logger
    }

    func callTool(name: String, arguments: [String: Value]?) async -> CallTool.Result {
        logger?.debug("Tool call received: \(name)")
        do {
            switch name {
            case HackerNewsSummaryToolCatalog.summarizeToolName:
                let result = try await handleSummarize(arguments: arguments)
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

    private func handleSummarize(arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let rawStories = arguments?["stories"]?.arrayValue?.compactMap({ $0.stringValue }), !rawStories.isEmpty else {
            throw HackerNewsSummaryToolError.invalidArguments("Argument 'stories' is required and must be a non-empty array of strings.")
        }

        if rawStories.count > 50 {
            throw HackerNewsSummaryToolError.invalidArguments("Argument 'stories' supports maximum 50 items per call.")
        }

        let language = arguments?["language"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let outputLanguage = language?.isEmpty == false ? language! : "ru"

        let stories = try parser.parseMany(rawStories)
        let summary = try await summarizeUseCase.execute(stories: stories, language: outputLanguage)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return .init(content: [.text(summary)], isError: false)
    }

    private static func errorResult(_ message: String) -> CallTool.Result {
        .init(content: [.text(message)], isError: true)
    }
}

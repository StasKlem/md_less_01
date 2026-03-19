import Foundation
import MCP

struct HackerNewsTranslateToolService: Sendable {
    private let translateUseCase: TranslateHackerNewsStoryUseCaseProtocol
    private let parser: HackerNewsStoryInputParser
    private let logger: Logger?

    init(
        translateUseCase: TranslateHackerNewsStoryUseCaseProtocol,
        parser: HackerNewsStoryInputParser = HackerNewsStoryInputParser(),
        logger: Logger? = nil
    ) {
        self.translateUseCase = translateUseCase
        self.parser = parser
        self.logger = logger
    }

    func callTool(name: String, arguments: [String: Value]?) async -> CallTool.Result {
        logger?.debug("Tool call received: \(name)")
        do {
            switch name {
            case HackerNewsTranslateToolCatalog.translateToolName:
                let result = try await handleTranslate(arguments: arguments)
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

    private func handleTranslate(arguments: [String: Value]?) async throws -> CallTool.Result {
        guard let rawStory = arguments?["story"]?.stringValue else {
            throw HackerNewsTranslateToolError.invalidArguments("Argument 'story' is required and must be a string.")
        }

        let trimmedStory = rawStory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedStory.isEmpty else {
            throw HackerNewsTranslateToolError.invalidArguments("Argument 'story' cannot be empty.")
        }

        let language = arguments?["language"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let outputLanguage = language?.isEmpty == false ? language! : "ru"

        let story = try parser.parse(trimmedStory)
        let translation = try await translateUseCase.execute(story: story, language: outputLanguage)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return .init(content: [.text(translation)], isError: false)
    }

    private static func errorResult(_ message: String) -> CallTool.Result {
        .init(content: [.text(message)], isError: true)
    }
}

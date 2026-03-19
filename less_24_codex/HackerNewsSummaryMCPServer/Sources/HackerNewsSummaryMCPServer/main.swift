import Foundation
import MCP

enum HackerNewsSummaryMCPServerApp {
    static func run() async -> Int32 {
        do {
            let config = try AppConfiguration.fromEnvironment()
            let logger = StderrLogger(component: "HackerNewsSummaryMCPServer", minLevel: config.logLevel)
            let repository = OpenAILLMHackerNewsSummaryRepository(
                config: .init(
                    baseURL: config.openAIBaseURL,
                    apiKey: config.openAIAPIKey,
                    model: config.openAIModel,
                    systemPrompt: config.systemPrompt
                )
            )
            let service = HackerNewsSummaryToolService(
                summarizeUseCase: SummarizeHackerNewsStoriesUseCase(repository: repository),
                logger: logger
            )

            logger.info("Starting MCP summary server with model: \(config.openAIModel)")

            let server = Server(
                name: "hacker-news-summary",
                version: "1.0.0",
                instructions: "Use hackernews_summarize_stories with an array of story text blocks produced by hackernews_get_random_story.",
                capabilities: .init(
                    tools: .init(listChanged: false)
                )
            )

            await server.withMethodHandler(ListTools.self) { _ in
                .init(tools: HackerNewsSummaryToolCatalog.tools)
            }

            await server.withMethodHandler(CallTool.self) { params in
                await service.callTool(name: params.name, arguments: params.arguments)
            }

            let transport = StdioTransport()
            try await server.start(transport: transport)
            await server.waitUntilCompleted()
            logger.info("Server stopped.")
            return 0
        } catch {
            let message = "HackerNewsSummaryMCPServer error: \(error.localizedDescription)"
            FileHandle.standardError.write(Data("\(message)\n".utf8))
            return 1
        }
    }
}

let exitCode = await HackerNewsSummaryMCPServerApp.run()
Foundation.exit(exitCode)

private struct AppConfiguration {
    let openAIBaseURL: URL
    let openAIAPIKey: String
    let openAIModel: String
    let systemPrompt: String?
    let logLevel: LogLevel

    static func fromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> AppConfiguration {
        let logLevel = try LogLevel.parse(environment["HACKERNEWS_SUMMARY_LOG_LEVEL"])

        let rawAPIKey = environment["HACKERNEWS_SUMMARY_OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let apiKey = rawAPIKey, !apiKey.isEmpty else {
            throw HackerNewsSummaryToolError.invalidArguments("HACKERNEWS_SUMMARY_OPENAI_API_KEY is required.")
        }

        let rawBaseURL = environment["HACKERNEWS_SUMMARY_OPENAI_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURLString = (rawBaseURL?.isEmpty == false) ? rawBaseURL! : "https://api.openai.com/v1"
        guard let baseURL = URL(string: baseURLString) else {
            throw HackerNewsSummaryToolError.invalidArguments("HACKERNEWS_SUMMARY_OPENAI_BASE_URL is not a valid URL.")
        }

        let rawModel = environment["HACKERNEWS_SUMMARY_OPENAI_MODEL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = (rawModel?.isEmpty == false) ? rawModel! : "gpt-4o-mini"

        let systemPrompt = environment["HACKERNEWS_SUMMARY_SYSTEM_PROMPT"]?.trimmingCharacters(in: .whitespacesAndNewlines)

        return AppConfiguration(
            openAIBaseURL: baseURL,
            openAIAPIKey: apiKey,
            openAIModel: model,
            systemPrompt: systemPrompt,
            logLevel: logLevel
        )
    }
}

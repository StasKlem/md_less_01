import Foundation
import MCP

enum HackerNewsTranslateMCPServerApp {
    static func run() async -> Int32 {
        do {
            let config = try AppConfiguration.fromEnvironment()
            let logger = StderrLogger(component: "HackerNewsTranslateMCPServer", minLevel: config.logLevel)
            let repository = OpenAILLMHackerNewsTranslateRepository(
                config: .init(
                    baseURL: config.openAIBaseURL,
                    apiKey: config.openAIAPIKey,
                    model: config.openAIModel,
                    systemPrompt: config.systemPrompt
                )
            )
            let service = HackerNewsTranslateToolService(
                translateUseCase: TranslateHackerNewsStoryUseCase(repository: repository),
                logger: logger
            )

            logger.info("Starting MCP translate server with model: \(config.openAIModel)")

            let server = Server(
                name: "hacker-news-translate",
                version: "1.0.0",
                instructions: "Use hackernews_translate_story with a story text block produced by hackernews_get_random_story.",
                capabilities: .init(
                    tools: .init(listChanged: false)
                )
            )

            await server.withMethodHandler(ListTools.self) { _ in
                .init(tools: HackerNewsTranslateToolCatalog.tools)
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
            let message = "HackerNewsTranslateMCPServer error: \(error.localizedDescription)"
            FileHandle.standardError.write(Data("\(message)\n".utf8))
            return 1
        }
    }
}

let exitCode = await HackerNewsTranslateMCPServerApp.run()
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
        let logLevel = try LogLevel.parse(environment["HACKERNEWS_TRANSLATE_LOG_LEVEL"])

        let rawAPIKey = environment["HACKERNEWS_TRANSLATE_OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let apiKey = rawAPIKey, !apiKey.isEmpty else {
            throw HackerNewsTranslateToolError.invalidArguments("HACKERNEWS_TRANSLATE_OPENAI_API_KEY is required.")
        }

        let rawBaseURL = environment["HACKERNEWS_TRANSLATE_OPENAI_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURLString = (rawBaseURL?.isEmpty == false) ? rawBaseURL! : "https://api.openai.com/v1"
        guard let baseURL = URL(string: baseURLString) else {
            throw HackerNewsTranslateToolError.invalidArguments("HACKERNEWS_TRANSLATE_OPENAI_BASE_URL is not a valid URL.")
        }

        let rawModel = environment["HACKERNEWS_TRANSLATE_OPENAI_MODEL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = (rawModel?.isEmpty == false) ? rawModel! : "gpt-4o-mini"

        let systemPrompt = environment["HACKERNEWS_TRANSLATE_SYSTEM_PROMPT"]?.trimmingCharacters(in: .whitespacesAndNewlines)

        return AppConfiguration(
            openAIBaseURL: baseURL,
            openAIAPIKey: apiKey,
            openAIModel: model,
            systemPrompt: systemPrompt,
            logLevel: logLevel
        )
    }
}

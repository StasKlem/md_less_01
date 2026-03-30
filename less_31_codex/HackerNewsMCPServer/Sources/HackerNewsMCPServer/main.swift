import Foundation
import MCP

enum HackerNewsMCPServerApp {
    static func run() async -> Int32 {
        do {
            let config = try AppConfiguration.fromEnvironment()
            let logger = StderrLogger(component: "HackerNewsMCPServer", minLevel: config.logLevel)
            let repository = HackerNewsAPIRepository(
                baseURL: config.baseURL,
                httpClient: URLSessionHTTPClient(logger: logger),
                randomGenerator: SystemRandomNumberGeneratorAdapter(),
                logger: logger
            )
            let service = HackerNewsToolService(
                randomStoryUseCase: GetRandomStoryUseCase(repository: repository),
                logger: logger
            )
            logger.info("Starting MCP server with base URL: \(config.baseURL.absoluteString)")

            let server = Server(
                name: "hacker-news",
                version: "1.0.0",
                instructions: "Use hackernews_get_random_story to fetch one random top story from Hacker News.",
                capabilities: .init(
                    tools: .init(listChanged: false)
                )
            )

            await server.withMethodHandler(ListTools.self) { _ in
                .init(tools: HackerNewsToolCatalog.tools)
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
            let message = "HackerNewsMCPServer error: \(error.localizedDescription)"
            FileHandle.standardError.write(Data("\(message)\n".utf8))
            return 1
        }
    }
}

let exitCode = await HackerNewsMCPServerApp.run()
Foundation.exit(exitCode)

private struct AppConfiguration {
    let baseURL: URL
    let logLevel: LogLevel

    static func fromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> AppConfiguration {
        let logLevel = try LogLevel.parse(environment["HACKERNEWS_LOG_LEVEL"])

        if let rawBaseURL = environment["HACKERNEWS_BASE_URL"], !rawBaseURL.isEmpty {
            guard let parsed = URL(string: rawBaseURL) else {
                throw HackerNewsToolError.invalidArguments(
                    "HACKERNEWS_BASE_URL is not a valid URL."
                )
            }
            return AppConfiguration(baseURL: parsed, logLevel: logLevel)
        }

        guard let defaultURL = URL(string: "https://hacker-news.firebaseio.com") else {
            throw HackerNewsToolError.upstreamFailure("Could not build default Hacker News base URL.")
        }
        return AppConfiguration(baseURL: defaultURL, logLevel: logLevel)
    }
}

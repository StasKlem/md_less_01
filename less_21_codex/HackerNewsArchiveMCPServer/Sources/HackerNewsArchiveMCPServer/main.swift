import Foundation
import MCP

enum HackerNewsArchiveMCPServerApp {
    static func run() async -> Int32 {
        do {
            let config = try AppConfiguration.fromEnvironment()
            let logger = StderrLogger(component: "HackerNewsArchiveMCPServer", minLevel: config.logLevel)
            let repository = FileHackerNewsArchiveRepository(storageDirectory: config.storageDirectory)
            let service = HackerNewsArchiveToolService(
                saveUseCase: SaveHackerNewsJSONUseCase(repository: repository),
                recentFilesUseCase: GetRecentHackerNewsFilesUseCase(repository: repository),
                logger: logger
            )

            logger.info("Starting MCP server with storage directory: \(config.storageDirectory.path)")

            let server = Server(
                name: "hacker-news-archive",
                version: "1.0.0",
                instructions: "Use hackernews_archive_save_json to save JSON and hackernews_archive_get_latest_files to return last 3 files.",
                capabilities: .init(
                    tools: .init(listChanged: false)
                )
            )

            await server.withMethodHandler(ListTools.self) { _ in
                .init(tools: HackerNewsArchiveToolCatalog.tools)
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
            let message = "HackerNewsArchiveMCPServer error: \(error.localizedDescription)"
            FileHandle.standardError.write(Data("\(message)\n".utf8))
            return 1
        }
    }
}

let exitCode = await HackerNewsArchiveMCPServerApp.run()
Foundation.exit(exitCode)

private struct AppConfiguration {
    let storageDirectory: URL
    let logLevel: LogLevel

    static func fromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> AppConfiguration {
        let logLevel = try LogLevel.parse(environment["HACKERNEWS_ARCHIVE_LOG_LEVEL"])

        if let rawDirectory = environment["HACKERNEWS_ARCHIVE_STORAGE_DIR"], !rawDirectory.isEmpty {
            let customURL = URL(fileURLWithPath: rawDirectory, isDirectory: true)
            return AppConfiguration(storageDirectory: customURL, logLevel: logLevel)
        }

        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let defaultDirectory = appSupport
            .appendingPathComponent("HackerNewsArchiveMCPServer", isDirectory: true)
            .appendingPathComponent("storage", isDirectory: true)

        return AppConfiguration(storageDirectory: defaultDirectory, logLevel: logLevel)
    }
}

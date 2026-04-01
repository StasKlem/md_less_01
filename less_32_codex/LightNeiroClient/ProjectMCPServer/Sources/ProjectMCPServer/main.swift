import Foundation
import MCP

enum ProjectMCPServerApp {
    static func run() async -> Int32 {
        do {
            let config = AppConfiguration.fromEnvironment()
            let logger = StderrLogger(component: "ProjectMCPServer", minLevel: config.logLevel)
            let repository = GitProjectRepository(rootDirectory: config.repositoryDirectory)
            let service = ProjectToolService(
                getCurrentGitBranchUseCase: GetCurrentGitBranchUseCase(repository: repository),
                listProjectFilesUseCase: ListProjectFilesUseCase(repository: repository),
                logger: logger
            )

            logger.info("Starting MCP server with repository directory: \(config.repositoryDirectory.path)")

            let server = Server(
                name: "project-mcp-server",
                version: "1.0.0",
                instructions: "Use project_git_branch to get the current git branch and project_list_files to get the list of project files.",
                capabilities: .init(
                    tools: .init(listChanged: false)
                )
            )

            await server.withMethodHandler(ListTools.self) { _ in
                .init(tools: ProjectToolCatalog.tools)
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
            let message = "ProjectMCPServer error: \(error.localizedDescription)"
            FileHandle.standardError.write(Data("\(message)\n".utf8))
            return 1
        }
    }
}

let exitCode = await ProjectMCPServerApp.run()
Foundation.exit(exitCode)

private struct AppConfiguration {
    let repositoryDirectory: URL
    let logLevel: LogLevel

    static func fromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> AppConfiguration {
        let logLevel = LogLevel.parse(environment["PROJECT_MCP_SERVER_LOG_LEVEL"])

        if let rawDirectory = environment["PROJECT_MCP_SERVER_REPOSITORY_ROOT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !rawDirectory.isEmpty
        {
            return AppConfiguration(
                repositoryDirectory: URL(fileURLWithPath: rawDirectory, isDirectory: true),
                logLevel: logLevel
            )
        }

        return AppConfiguration(
            repositoryDirectory: URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true),
            logLevel: logLevel
        )
    }
}

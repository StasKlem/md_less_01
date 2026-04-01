import Foundation
import MCP
import Logging

final class MCPToolDiscoveryService: MCPToolDiscoveryServiceProtocol, MCPWeatherServiceProtocol, MCPHackerNewsServiceProtocol, ProjectGitBranchServiceProtocol {
    private let clientFactory: @Sendable () -> Client
    private let hackerNewsTranslateEnvironmentProvider: (@Sendable (UUID) async -> [String: String])?
    private let projectEnvironmentProvider: (@Sendable () -> [String: String])?

    init(clientFactory: @escaping @Sendable () -> Client = {
        Client(name: "LightNeiroClient", version: "1.0.0")
    },
    hackerNewsTranslateEnvironmentProvider: (@Sendable (UUID) async -> [String: String])? = nil,
    projectEnvironmentProvider: (@Sendable () -> [String: String])? = nil) {
        self.clientFactory = clientFactory
        self.hackerNewsTranslateEnvironmentProvider = hackerNewsTranslateEnvironmentProvider
        self.projectEnvironmentProvider = projectEnvironmentProvider
    }

    func fetchTools(serverURL: URL) async throws -> [MCPToolSummary] {
        let client = clientFactory()
        let transport = try makeTransport(serverURL: serverURL, environmentOverrides: nil)

        do {
            _ = try await client.connect(transport: transport)
            let result = try await client.listTools()
            await client.disconnect()
            return result.tools
                .map { MCPToolSummary(name: $0.name, description: $0.description) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            await client.disconnect()
            throw error
        }
    }

    func fetchCurrentGitBranch(serverURL: URL) async throws -> ProjectGitBranchContext {
        let client = clientFactory()
        do {
            let transport = try makeTransport(
                serverURL: serverURL,
                environmentOverrides: projectEnvironmentProvider?()
            )
            _ = try await client.connect(transport: transport)
            let result = try await client.callTool(name: "project_git_branch", arguments: [:])
            await client.disconnect()

            let text = extractText(from: result.content)
            if result.isError ?? false {
                let reason = text.isEmpty ? "MCP project_git_branch returned an error." : text
                if let fallback = localCurrentGitBranch(), !fallback.isEmpty {
                    return ProjectGitBranchContext(
                        branch: fallback,
                        diagnosticMessage: "MCP project_git_branch завершился ошибкой: \(reason). Использована локальная ветка \(fallback)."
                    )
                }
                return ProjectGitBranchContext(
                    branch: nil,
                    diagnosticMessage: "MCP project_git_branch завершился ошибкой: \(reason)"
                )
            }
            guard !text.isEmpty else {
                if let fallback = localCurrentGitBranch(), !fallback.isEmpty {
                    return ProjectGitBranchContext(
                        branch: fallback,
                        diagnosticMessage: "MCP project_git_branch вернул пустой ответ. Использована локальная ветка \(fallback)."
                    )
                }
                return ProjectGitBranchContext(
                    branch: nil,
                    diagnosticMessage: "MCP project_git_branch вернул пустой ответ."
                )
            }
            return ProjectGitBranchContext(branch: text, diagnosticMessage: nil)
        } catch {
            await client.disconnect()
            if let fallback = localCurrentGitBranch(), !fallback.isEmpty {
                return ProjectGitBranchContext(
                    branch: fallback,
                    diagnosticMessage: "Не удалось получить текущую git-ветку через MCP: \(error.localizedDescription). Использована локальная ветка \(fallback)."
                )
            }
            return ProjectGitBranchContext(
                branch: nil,
                diagnosticMessage: "Не удалось получить текущую git-ветку через MCP: \(error.localizedDescription)"
            )
        }
    }

    func fetchProjectFiles(serverURL: URL) async throws -> ProjectFilesContext {
        let client = clientFactory()
        do {
            let transport = try makeTransport(
                serverURL: serverURL,
                environmentOverrides: projectEnvironmentProvider?()
            )
            _ = try await client.connect(transport: transport)
            let result = try await client.callTool(name: "project_list_files", arguments: [:])
            await client.disconnect()

            let text = extractText(from: result.content)
            if result.isError ?? false {
                let reason = text.isEmpty ? "MCP project_list_files returned an error." : text
                let fallback = localProjectFiles()
                if !fallback.isEmpty {
                    return ProjectFilesContext(
                        files: fallback,
                        diagnosticMessage: "MCP project_list_files завершился ошибкой: \(reason). Использован локальный список файлов."
                    )
                }
                return ProjectFilesContext(
                    files: [],
                    diagnosticMessage: "MCP project_list_files завершился ошибкой: \(reason)"
                )
            }
            guard !text.isEmpty else {
                let fallback = localProjectFiles()
                if !fallback.isEmpty {
                    return ProjectFilesContext(
                        files: fallback,
                        diagnosticMessage: "MCP project_list_files вернул пустой ответ. Использован локальный список файлов."
                    )
                }
                return ProjectFilesContext(
                    files: [],
                    diagnosticMessage: "MCP project_list_files вернул пустой ответ."
                )
            }
            return ProjectFilesContext(files: parseProjectFiles(from: text), diagnosticMessage: nil)
        } catch {
            await client.disconnect()
            let fallback = localProjectFiles()
            if !fallback.isEmpty {
                return ProjectFilesContext(
                    files: fallback,
                    diagnosticMessage: "Не удалось получить список файлов проекта через MCP: \(error.localizedDescription). Использован локальный список файлов."
                )
            }
            return ProjectFilesContext(
                files: [],
                diagnosticMessage: "Не удалось получить список файлов проекта через MCP: \(error.localizedDescription)"
            )
        }
    }

    func fetchCurrentWeather(
        serverURL: URL,
        city: String,
        units: String = "metric",
        language: String? = nil
    ) async throws -> String {
        let normalizedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCity.isEmpty else {
            throw MCPDiscoveryError.toolCall("City is required for weather request.")
        }

        let client = clientFactory()
        let transport = try makeTransport(serverURL: serverURL, environmentOverrides: nil)

        var arguments: [String: Value] = [
            "city": .string(normalizedCity),
            "units": .string(units)
        ]
        if let language = language?.trimmingCharacters(in: .whitespacesAndNewlines),
           !language.isEmpty
        {
            arguments["lang"] = .string(language)
        }

        do {
            _ = try await client.connect(transport: transport)
            let result = try await client.callTool(name: "weather_get_current", arguments: arguments)
            await client.disconnect()

            let text = extractText(from: result.content)
            if result.isError ?? false {
                throw MCPDiscoveryError.toolCall(text.isEmpty ? "MCP weather_get_current returned an error." : text)
            }
            guard !text.isEmpty else {
                throw MCPDiscoveryError.toolCall("MCP weather_get_current returned empty response.")
            }
            return text
        } catch {
            await client.disconnect()
            throw error
        }
    }

    func fetchRandomStory(serverURL: URL) async throws -> HackerNewsTaskAgentStory {
        let client = clientFactory()
        let transport = try makeTransport(serverURL: serverURL, environmentOverrides: nil)

        do {
            _ = try await client.connect(transport: transport)
            let result = try await client.callTool(name: "hackernews_get_random_story", arguments: [:])
            await client.disconnect()

            let text = extractText(from: result.content)
            if result.isError ?? false {
                throw MCPDiscoveryError.toolCall(text.isEmpty ? "MCP hackernews_get_random_story returned an error." : text)
            }
            guard !text.isEmpty else {
                throw MCPDiscoveryError.toolCall("MCP hackernews_get_random_story returned empty response.")
            }
            return parseHackerNewsStory(from: text)
        } catch {
            await client.disconnect()
            throw error
        }
    }

    func translateStory(serverURL: URL, sessionID: UUID, story: String, language: String) async throws -> String {
        let trimmedStory = story.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedStory.isEmpty else {
            throw MCPDiscoveryError.toolCall("Story text is required for translation.")
        }

        let normalizedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)
        let outputLanguage = normalizedLanguage.isEmpty ? "ru" : normalizedLanguage

        let client = clientFactory()
        let envOverrides = await hackerNewsTranslateEnvironmentProvider?(sessionID)
        let transport = try makeTransport(serverURL: serverURL, environmentOverrides: envOverrides)

        do {
            _ = try await client.connect(transport: transport)
            let result = try await client.callTool(
                name: "hackernews_translate_story",
                arguments: [
                    "story": .string(trimmedStory),
                    "language": .string(outputLanguage)
                ]
            )
            await client.disconnect()

            let text = extractText(from: result.content)
            if result.isError ?? false {
                throw MCPDiscoveryError.toolCall(text.isEmpty ? "MCP hackernews_translate_story returned an error." : text)
            }
            guard !text.isEmpty else {
                throw MCPDiscoveryError.toolCall("MCP hackernews_translate_story returned empty response.")
            }
            return text
        } catch {
            await client.disconnect()
            throw error
        }
    }

    func saveArchiveJSON(serverURL: URL, json: String) async throws -> String {
        let trimmedJSON = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedJSON.isEmpty else {
            throw MCPDiscoveryError.toolCall("JSON payload is required for archiving.")
        }

        let client = clientFactory()
        let transport = try makeTransport(serverURL: serverURL, environmentOverrides: nil)

        do {
            _ = try await client.connect(transport: transport)
            let result = try await client.callTool(
                name: "hackernews_archive_save_json",
                arguments: ["json": .string(trimmedJSON)]
            )
            await client.disconnect()

            let text = extractText(from: result.content)
            if result.isError ?? false {
                throw MCPDiscoveryError.toolCall(text.isEmpty ? "MCP hackernews_archive_save_json returned an error." : text)
            }
            guard !text.isEmpty else {
                throw MCPDiscoveryError.toolCall("MCP hackernews_archive_save_json returned empty response.")
            }
            return text
        } catch {
            await client.disconnect()
            throw error
        }
    }

    private func makeTransport(serverURL: URL, environmentOverrides: [String: String]?) throws -> any Transport {
        if shouldUseStdio(serverURL: serverURL) {
            let configuration = try buildStdioLaunchConfiguration(
                serverURL: serverURL,
                environmentOverrides: environmentOverrides
            )
            return ProcessStdioMCPTransport(launchConfiguration: configuration)
        }
        return HTTPClientTransport(endpoint: serverURL, streaming: true)
    }

    private func localCurrentGitBranch() -> String? {
        guard let repositoryRoot = findRepositoryRoot() else {
            return nil
        }

        if let branch = runGit(arguments: ["branch", "--show-current"], currentDirectoryURL: repositoryRoot),
           !branch.isEmpty
        {
            return branch
        }

        if let sha = runGit(arguments: ["rev-parse", "--short", "HEAD"], currentDirectoryURL: repositoryRoot),
           !sha.isEmpty
        {
            return "detached HEAD (\(sha))"
        }

        return nil
    }

    private func localProjectFiles() -> [String] {
        guard let repositoryRoot = findRepositoryRoot(),
              let output = runGit(
                arguments: ["ls-files", "--cached", "--others", "--exclude-standard"],
                currentDirectoryURL: repositoryRoot
              )
        else {
            return []
        }

        return output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func shouldUseStdio(serverURL: URL) -> Bool {
        switch serverURL.scheme?.lowercased() {
        case "stdio", "file":
            return true
        default:
            return false
        }
    }

    private func buildStdioLaunchConfiguration(
        serverURL: URL,
        environmentOverrides: [String: String]?
    ) throws -> ProcessStdioMCPTransport.LaunchConfiguration {
        if serverURL.isFileURL {
            return .init(
                executableURL: serverURL,
                arguments: [],
                currentDirectoryURL: nil,
                environmentOverrides: environmentOverrides
            )
        }

        let serverKind = try inferStdioServerKind(from: serverURL)
        var environment = ProcessInfo.processInfo.environment
        if let environmentOverrides {
            for (key, value) in environmentOverrides {
                environment[key] = value
            }
        }
        var invalidExplicitPathMessage: String?
        if let explicitPath = environment[serverKind.explicitPathEnv]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !explicitPath.isEmpty
        {
            if let configuration = buildLaunchConfigurationFromExplicitPath(
                explicitPath,
                serverKind: serverKind,
                environmentOverrides: environmentOverrides
            ) {
                return configuration
            }
            invalidExplicitPathMessage = "\(serverKind.explicitPathEnv) points to missing path: \(explicitPath)"
        }

        if let packageDirectory = findPackageDirectory(named: serverKind.packageDirectoryName) {
            let scratchPath = swiftPackageScratchPath(for: packageDirectory)
            return .init(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: [
                    "swift",
                    "run",
                    "--package-path",
                    packageDirectory.path,
                    "--scratch-path",
                    scratchPath.path,
                    serverKind.executableName
                ],
                currentDirectoryURL: packageDirectory,
                environmentOverrides: environmentOverrides
            )
        }

        if let invalidExplicitPathMessage {
            throw MCPDiscoveryError.configuration(
                "\(invalidExplicitPathMessage). Also failed to auto-detect \(serverKind.packageDirectoryName) in current workspace hierarchy."
            )
        }

        throw MCPDiscoveryError.configuration(
            "\(serverKind.readableName) MCP server not found. Set \(serverKind.explicitPathEnv) or use HTTP endpoint."
        )
    }

    private func buildLaunchConfigurationFromExplicitPath(
        _ explicitPath: String,
        serverKind: MCPStdioServerKind,
        environmentOverrides: [String: String]?
    ) -> ProcessStdioMCPTransport.LaunchConfiguration? {
        let fileManager = FileManager.default
        guard let resolvedURL = resolveExistingPath(explicitPath, fileManager: fileManager) else {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory) else {
            return nil
        }

        if isDirectory.boolValue {
            let packageManifest = resolvedURL.appendingPathComponent("Package.swift")
            guard fileManager.fileExists(atPath: packageManifest.path) else {
                let nestedPackageDirectory = resolvedURL
                    .appendingPathComponent(serverKind.packageDirectoryName, isDirectory: true)
                let nestedPackageManifest = nestedPackageDirectory.appendingPathComponent("Package.swift")
                guard fileManager.fileExists(atPath: nestedPackageManifest.path) else {
                    return nil
                }
                return .init(
                    executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                    arguments: [
                        "swift",
                        "run",
                        "--package-path",
                        nestedPackageDirectory.path,
                        "--scratch-path",
                        swiftPackageScratchPath(for: nestedPackageDirectory).path,
                        serverKind.executableName
                    ],
                    currentDirectoryURL: nestedPackageDirectory,
                    environmentOverrides: environmentOverrides
                )
            }
            return .init(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: [
                    "swift",
                    "run",
                    "--package-path",
                    resolvedURL.path,
                    "--scratch-path",
                    swiftPackageScratchPath(for: resolvedURL).path,
                    serverKind.executableName
                ],
                currentDirectoryURL: resolvedURL,
                environmentOverrides: environmentOverrides
            )
        }

        return .init(
            executableURL: resolvedURL,
            arguments: [],
            currentDirectoryURL: nil,
            environmentOverrides: environmentOverrides
        )
    }

    private func resolveExistingPath(_ path: String, fileManager: FileManager) -> URL? {
        let directURL = URL(fileURLWithPath: path)
        if fileManager.fileExists(atPath: directURL.path) {
            return directURL
        }

        var cursor = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        for _ in 0...20 {
            let candidate = cursor.appendingPathComponent(path)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path {
                break
            }
            cursor = parent
        }
        return nil
    }

    private func inferStdioServerKind(from serverURL: URL) throws -> MCPStdioServerKind {
        let hint = serverURL.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch hint {
        case "open-weather":
            return .openWeather
        case "hackernews", "hacker-news":
            return .hackerNews
        case "hackernews-translate", "hacker-news-translate":
            return .hackerNewsTranslate
        case "hackernews-archive", "hacker-news-archive":
            return .hackerNewsArchive
        case "project":
            return .project
        default:
            throw MCPDiscoveryError.configuration(
                "Unknown stdio MCP endpoint: \(serverURL.absoluteString). Expected stdio://open-weather, stdio://hackernews, stdio://hackernews-translate, stdio://hackernews-archive, or stdio://project."
            )
        }
    }

    private func findPackageDirectory(named directoryName: String) -> URL? {
        let fileManager = FileManager.default
        var cursor = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)

        for _ in 0...20 {
            let packageCandidate = cursor.appendingPathComponent(directoryName, isDirectory: true)
            let packageManifest = packageCandidate.appendingPathComponent("Package.swift")
            if fileManager.fileExists(atPath: packageManifest.path) {
                return packageCandidate
            }

            let localManifest = cursor.appendingPathComponent("Package.swift")
            if fileManager.fileExists(atPath: localManifest.path),
               cursor.lastPathComponent == directoryName
            {
                return cursor
            }

            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path {
                break
            }
            cursor = parent
        }
        return nil
    }

    private func findRepositoryRoot() -> URL? {
        let fileManager = FileManager.default

        if let topLevelPath = runGit(
            arguments: ["rev-parse", "--show-toplevel"],
            currentDirectoryURL: nil
        ),
        !topLevelPath.isEmpty
        {
            let topLevelURL = URL(fileURLWithPath: topLevelPath, isDirectory: true)
            if fileManager.fileExists(atPath: topLevelURL.path) {
                return topLevelURL
            }
        }

        var cursor = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)

        for _ in 0...10 {
            let gitDirectory = cursor.appendingPathComponent(".git", isDirectory: true)
            if fileManager.fileExists(atPath: gitDirectory.path) {
                return cursor
            }

            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path {
                break
            }
            cursor = parent
        }
        return nil
    }

    private func swiftPackageScratchPath(for packageDirectory: URL) -> URL {
        let scratchRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("lightneiro-swiftpm", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: scratchRoot,
            withIntermediateDirectories: true
        )
        let packageIdentifier = stablePathIdentifier(packageDirectory.path)
        return scratchRoot.appendingPathComponent(packageIdentifier, isDirectory: true)
    }

    private func stablePathIdentifier(_ path: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16, uppercase: false)
    }
}

private extension MCPToolDiscoveryService {
    func runGit(arguments: [String], currentDirectoryURL: URL?) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum MCPStdioServerKind {
    case openWeather
    case hackerNews
    case hackerNewsTranslate
    case hackerNewsArchive
    case project

    var explicitPathEnv: String {
        switch self {
        case .openWeather:
            return "OPENWEATHER_MCP_SERVER_PATH"
        case .hackerNews:
            return "HACKERNEWS_MCP_SERVER_PATH"
        case .hackerNewsTranslate:
            return "HACKERNEWS_TRANSLATE_MCP_SERVER_PATH"
        case .hackerNewsArchive:
            return "HACKERNEWS_ARCHIVE_MCP_SERVER_PATH"
        case .project:
            return "PROJECT_MCP_SERVER_PATH"
        }
    }

    var packageDirectoryName: String {
        switch self {
        case .openWeather:
            return "OpenWeatherMCPServer"
        case .hackerNews:
            return "HackerNewsMCPServer"
        case .hackerNewsTranslate:
            return "HackerNewsTranslateMCPServer"
        case .hackerNewsArchive:
            return "HackerNewsArchiveMCPServer"
        case .project:
            return "ProjectMCPServer"
        }
    }

    var executableName: String {
        packageDirectoryName
    }

    var readableName: String {
        switch self {
        case .openWeather:
            return "OpenWeather"
        case .hackerNews:
            return "HackerNews"
        case .hackerNewsTranslate:
            return "HackerNewsTranslate"
        case .hackerNewsArchive:
            return "HackerNewsArchive"
        case .project:
            return "ProjectMCPServer"
        }
    }
}

private func parseHackerNewsStory(from text: String) -> HackerNewsTaskAgentStory {
    let lines = text
        .split(separator: "\n")
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

    let title = extractHNField(prefix: "- Title:", lines: lines) ?? "Untitled Hacker News story"
    let id = extractHNField(prefix: "- ID:", lines: lines).flatMap(Int.init)
    let author = extractHNField(prefix: "- Author:", lines: lines)
    let score = extractHNField(prefix: "- Score:", lines: lines).flatMap(Int.init)
    let timestamp = extractHNField(prefix: "- Time:", lines: lines)
    let urlValue = extractHNField(prefix: "- URL:", lines: lines)
    let normalizedURL = normalizeHNURL(urlValue)

    return HackerNewsTaskAgentStory(
        storyID: id,
        title: title,
        author: author,
        score: score,
        publishedAtUTC: timestamp,
        url: normalizedURL,
        rawText: text
    )
}

private func extractHNField(prefix: String, lines: [String]) -> String? {
    guard let line = lines.first(where: { $0.hasPrefix(prefix) }) else { return nil }
    let value = line
        .replacingOccurrences(of: prefix, with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
}

private func normalizeHNURL(_ value: String?) -> String? {
    guard let value else { return nil }
    if value == "(no external URL)" {
        return nil
    }
    return value
}

private func extractText(from content: [Tool.Content]) -> String {
    content.compactMap {
        guard case .text(let text) = $0 else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    .filter { !$0.isEmpty }
    .joined(separator: "\n")
}

private func parseProjectFiles(from text: String) -> [String] {
    let lines = text
        .split(separator: "\n")
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    guard !lines.isEmpty else {
        return []
    }

    let candidateLines: [String]
    if lines.first?.lowercased().hasPrefix("project files") == true {
        candidateLines = Array(lines.dropFirst())
    } else {
        candidateLines = lines
    }

    return candidateLines
        .map { line -> String in
            var normalized = line
            if normalized.hasPrefix("- ") {
                normalized.removeFirst(2)
            } else if normalized.hasPrefix("• ") {
                normalized.removeFirst(2)
            }
            return normalized
        }
        .filter { !$0.isEmpty }
}

private actor ProcessStdioMCPTransport: Transport {
    struct LaunchConfiguration: Sendable {
        let executableURL: URL
        let arguments: [String]
        let currentDirectoryURL: URL?
        let environmentOverrides: [String: String]?
    }

    nonisolated let logger: Logger
    private let appLogger: AppLogger

    private let launchConfiguration: LaunchConfiguration
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var isConnected = false
    private var pendingData = Data()
    private var stderrLines: [String] = []
    private let messageStream: AsyncThrowingStream<Data, Swift.Error>
    private let messageContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation

    init(launchConfiguration: LaunchConfiguration, logger: AppLogger = .shared) {
        self.launchConfiguration = launchConfiguration
        self.logger = Logger(label: "mcp.transport.process-stdio")
        self.appLogger = logger

        var continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation!
        self.messageStream = AsyncThrowingStream { continuation = $0 }
        self.messageContinuation = continuation
    }

    func connect() async throws {
        guard !isConnected else { return }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = launchConfiguration.executableURL
        process.arguments = launchConfiguration.arguments
        process.currentDirectoryURL = launchConfiguration.currentDirectoryURL
        if let environmentOverrides = launchConfiguration.environmentOverrides,
           !environmentOverrides.isEmpty
        {
            var environment = ProcessInfo.processInfo.environment
            for (key, value) in environmentOverrides {
                environment[key] = value
            }
            process.environment = environment
        }
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { await self?.handleStdoutChunk(data) }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { await self?.handleStderrChunk(data) }
        }

        process.terminationHandler = { [weak self] terminatedProcess in
            Task { await self?.handleTermination(status: terminatedProcess.terminationStatus) }
        }

        do {
            try process.run()
        } catch {
            appLogger.error(
                "Не удалось запустить MCP процесс: \(error.localizedDescription)",
                category: "mcp.transport.process-stdio"
            )
            throw MCPDiscoveryError.transport("Failed to start MCP process: \(error.localizedDescription)")
        }

        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe
        self.isConnected = true
    }

    func disconnect() async {
        guard isConnected else { return }
        isConnected = false

        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil

        try? inputPipe?.fileHandleForWriting.close()
        try? outputPipe?.fileHandleForReading.close()
        try? errorPipe?.fileHandleForReading.close()

        if let process, process.isRunning {
            process.terminate()
        }

        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
        process = nil
        pendingData = Data()
        stderrLines.removeAll(keepingCapacity: false)
        messageContinuation.finish()
    }

    func send(_ data: Data) async throws {
        guard isConnected, let writer = inputPipe?.fileHandleForWriting else {
            throw MCPDiscoveryError.transport("MCP stdio transport is not connected.")
        }

        var payload = data
        payload.append(UInt8(ascii: "\n"))
        do {
            try writer.write(contentsOf: payload)
        } catch {
            throw MCPDiscoveryError.transport("Failed to write MCP message: \(error.localizedDescription)")
        }
    }

    func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        messageStream
    }

    private func handleStdoutChunk(_ data: Data) {
        guard isConnected else { return }
        guard !data.isEmpty else {
            messageContinuation.finish()
            return
        }

        pendingData.append(data)
        while let newlineIndex = pendingData.firstIndex(of: UInt8(ascii: "\n")) {
            let message = Data(pendingData[..<newlineIndex])
            pendingData.removeSubrange(...newlineIndex)
            if !message.isEmpty {
                messageContinuation.yield(message)
            }
        }
    }

    private func handleStderrChunk(_ data: Data) {
        guard !data.isEmpty else { return }
        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        {
            for line in text.split(separator: "\n").map({ String($0) }) {
                stderrLines.append(line)
            }
            if stderrLines.count > 20 {
                stderrLines = Array(stderrLines.suffix(20))
            }
            appLogger.debug("MCP stderr: \(text)", category: "mcp.transport.process-stdio")
        }
    }

    private func handleTermination(status: Int32) {
        guard isConnected else { return }
        isConnected = false
        if status != 0 {
            let stderrSuffix = stderrLines.isEmpty ? "" : ". stderr: \(stderrLines.joined(separator: " | "))"
            let message = "MCP process exited with code \(status)\(stderrSuffix)"
            appLogger.error(message, category: "mcp.transport.process-stdio")
            messageContinuation.finish(throwing: MCPDiscoveryError.transport(message))
            return
        }
        messageContinuation.finish()
    }
}

private enum MCPDiscoveryError: LocalizedError {
    case configuration(String)
    case transport(String)
    case toolCall(String)

    var errorDescription: String? {
        switch self {
        case .configuration(let message), .transport(let message), .toolCall(let message):
            return message
        }
    }
}

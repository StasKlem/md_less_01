import Foundation
import MCP
import Logging

final class MCPToolDiscoveryService: MCPToolDiscoveryServiceProtocol, MCPWeatherServiceProtocol, MCPHackerNewsServiceProtocol {
    private let clientFactory: @Sendable () -> Client

    init(clientFactory: @escaping @Sendable () -> Client = {
        Client(name: "LightNeiroClient", version: "1.0.0")
    }) {
        self.clientFactory = clientFactory
    }

    func fetchTools(serverURL: URL) async throws -> [MCPToolSummary] {
        let client = clientFactory()
        let transport = try makeTransport(serverURL: serverURL)

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
        let transport = try makeTransport(serverURL: serverURL)

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
        let transport = try makeTransport(serverURL: serverURL)

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

    private func makeTransport(serverURL: URL) throws -> any Transport {
        if shouldUseStdio(serverURL: serverURL) {
            let configuration = try buildStdioLaunchConfiguration(serverURL: serverURL)
            return ProcessStdioMCPTransport(launchConfiguration: configuration)
        }
        return HTTPClientTransport(endpoint: serverURL, streaming: true)
    }

    private func shouldUseStdio(serverURL: URL) -> Bool {
        switch serverURL.scheme?.lowercased() {
        case "stdio", "file":
            return true
        default:
            return false
        }
    }

    private func buildStdioLaunchConfiguration(serverURL: URL) throws -> ProcessStdioMCPTransport.LaunchConfiguration {
        if serverURL.isFileURL {
            return .init(executableURL: serverURL, arguments: [], currentDirectoryURL: nil)
        }

        let serverKind = try inferStdioServerKind(from: serverURL)
        let environment = ProcessInfo.processInfo.environment
        if let explicitPath = environment[serverKind.explicitPathEnv]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !explicitPath.isEmpty
        {
            if let configuration = buildLaunchConfigurationFromExplicitPath(
                explicitPath,
                serverKind: serverKind
            ) {
                return configuration
            }
            throw MCPDiscoveryError.configuration(
                "\(serverKind.explicitPathEnv) points to missing path: \(explicitPath)"
            )
        }

        if let packageDirectory = findPackageDirectory(named: serverKind.packageDirectoryName) {
            return .init(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: [
                    "swift",
                    "run",
                    "--package-path",
                    packageDirectory.path,
                    serverKind.executableName
                ],
                currentDirectoryURL: packageDirectory
            )
        }

        throw MCPDiscoveryError.configuration(
            "\(serverKind.readableName) MCP server not found. Set \(serverKind.explicitPathEnv) or use HTTP endpoint."
        )
    }

    private func buildLaunchConfigurationFromExplicitPath(
        _ explicitPath: String,
        serverKind: MCPStdioServerKind
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
                return nil
            }
            return .init(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: [
                    "swift",
                    "run",
                    "--package-path",
                    resolvedURL.path,
                    serverKind.executableName
                ],
                currentDirectoryURL: resolvedURL
            )
        }

        return .init(executableURL: resolvedURL, arguments: [], currentDirectoryURL: nil)
    }

    private func resolveExistingPath(_ path: String, fileManager: FileManager) -> URL? {
        let directURL = URL(fileURLWithPath: path)
        if fileManager.fileExists(atPath: directURL.path) {
            return directURL
        }

        var cursor = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        for _ in 0...8 {
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
        default:
            throw MCPDiscoveryError.configuration(
                "Unknown stdio MCP endpoint: \(serverURL.absoluteString). Expected stdio://open-weather or stdio://hackernews."
            )
        }
    }

    private func findPackageDirectory(named directoryName: String) -> URL? {
        let fileManager = FileManager.default
        var cursor = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)

        for _ in 0...8 {
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
}

private enum MCPStdioServerKind {
    case openWeather
    case hackerNews

    var explicitPathEnv: String {
        switch self {
        case .openWeather:
            return "OPENWEATHER_MCP_SERVER_PATH"
        case .hackerNews:
            return "HACKERNEWS_MCP_SERVER_PATH"
        }
    }

    var packageDirectoryName: String {
        switch self {
        case .openWeather:
            return "OpenWeatherMCPServer"
        case .hackerNews:
            return "HackerNewsMCPServer"
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

private actor ProcessStdioMCPTransport: Transport {
    struct LaunchConfiguration: Sendable {
        let executableURL: URL
        let arguments: [String]
        let currentDirectoryURL: URL?
    }

    nonisolated let logger: Logger

    private let launchConfiguration: LaunchConfiguration
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var isConnected = false
    private var pendingData = Data()
    private let messageStream: AsyncThrowingStream<Data, Swift.Error>
    private let messageContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation

    init(launchConfiguration: LaunchConfiguration, logger: Logger? = nil) {
        self.launchConfiguration = launchConfiguration
        self.logger = logger ?? Logger(label: "mcp.transport.process-stdio")

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
            logger.debug("MCP stderr: \(text)")
        }
    }

    private func handleTermination(status: Int32) {
        guard isConnected else { return }
        isConnected = false
        if status != 0 {
            logger.error("MCP process exited with code \(status)")
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

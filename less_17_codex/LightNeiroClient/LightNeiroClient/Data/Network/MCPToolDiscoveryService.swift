import Foundation
import MCP
import Logging

final class MCPToolDiscoveryService: MCPToolDiscoveryServiceProtocol {
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

        let environment = ProcessInfo.processInfo.environment
        if let explicitPath = environment["OPENWEATHER_MCP_SERVER_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !explicitPath.isEmpty
        {
            return .init(
                executableURL: URL(fileURLWithPath: explicitPath),
                arguments: [],
                currentDirectoryURL: nil
            )
        }

        if let packageDirectory = findOpenWeatherPackageDirectory() {
            return .init(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: [
                    "swift",
                    "run",
                    "--package-path",
                    packageDirectory.path,
                    "OpenWeatherMCPServer"
                ],
                currentDirectoryURL: packageDirectory
            )
        }

        throw MCPDiscoveryError.configuration(
            "OpenWeather MCP server not found. Set OPENWEATHER_MCP_SERVER_PATH or use HTTP endpoint."
        )
    }

    private func findOpenWeatherPackageDirectory() -> URL? {
        let fileManager = FileManager.default
        var cursor = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)

        for _ in 0...8 {
            let packageCandidate = cursor.appendingPathComponent("OpenWeatherMCPServer", isDirectory: true)
            let packageManifest = packageCandidate.appendingPathComponent("Package.swift")
            if fileManager.fileExists(atPath: packageManifest.path) {
                return packageCandidate
            }

            let localManifest = cursor.appendingPathComponent("Package.swift")
            if fileManager.fileExists(atPath: localManifest.path),
               cursor.lastPathComponent == "OpenWeatherMCPServer"
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
            logger.debug("OpenWeather MCP stderr: \(text)")
        }
    }

    private func handleTermination(status: Int32) {
        guard isConnected else { return }
        isConnected = false
        if status != 0 {
            logger.error("OpenWeather MCP process exited with code \(status)")
        }
        messageContinuation.finish()
    }
}

private enum MCPDiscoveryError: LocalizedError {
    case configuration(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .configuration(let message), .transport(let message):
            return message
        }
    }
}

import Foundation
import XCTest

final class MCPProjectServerIntegrationTests: XCTestCase {
    func testProjectServerExposesBranchToolAndReturnsCurrentBranch() throws {
        let packageDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ProjectMCPServer")
        let repositoryRoot = packageDirectory.deletingLastPathComponent()

        let buildDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lnc-project-mcp-\(UUID().uuidString)", isDirectory: true)

        try buildProjectMCPServer(
            at: packageDirectory,
            buildDirectory: buildDirectory
        )

        let executableURL = buildDirectory
            .appendingPathComponent("debug/ProjectMCPServer")

        let output = try runProjectMCPServer(
            executableURL: executableURL,
            repositoryRoot: repositoryRoot
        )

        XCTAssertTrue(output.contains("project_git_branch"), "Ответ сервера: \(output)")
        XCTAssertTrue(output.contains("\"text\":\"main\""), "Ответ сервера: \(output)")
    }

    func testProjectServerExposesFileListingToolAndReturnsProjectFiles() throws {
        let packageDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ProjectMCPServer")
        let repositoryRoot = packageDirectory.deletingLastPathComponent()

        let buildDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lnc-project-mcp-\(UUID().uuidString)", isDirectory: true)

        try buildProjectMCPServer(
            at: packageDirectory,
            buildDirectory: buildDirectory
        )

        let executableURL = buildDirectory
            .appendingPathComponent("debug/ProjectMCPServer")

        let output = try runProjectMCPServer(
            executableURL: executableURL,
            repositoryRoot: repositoryRoot
        )

        XCTAssertTrue(output.contains("project_list_files"), "Ответ сервера: \(output)")
        XCTAssertTrue(output.contains("ProjectMCPServer/Package.swift"), "Ответ сервера: \(output)")
    }

    private func buildProjectMCPServer(at packageDirectory: URL, buildDirectory: URL) throws {
        try FileManager.default.createDirectory(
            at: buildDirectory,
            withIntermediateDirectories: true
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "swift",
            "build",
            "--package-path",
            packageDirectory.path,
            "--build-path",
            buildDirectory.path,
            "-c",
            "debug"
        ]
        process.currentDirectoryURL = packageDirectory

        let devNull = FileHandle(forWritingAtPath: "/dev/null")
        process.standardOutput = devNull
        process.standardError = devNull

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "MCPProjectServerIntegrationTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Не удалось собрать ProjectMCPServer."]
            )
        }
    }

    private func runProjectMCPServer(executableURL: URL, repositoryRoot: URL) throws -> String {
        let process = Process()
        process.executableURL = executableURL
        process.environment = [
            "PROJECT_MCP_SERVER_REPOSITORY_ROOT": repositoryRoot.path
        ]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")

        try process.run()

        let payloads = [
            makeRequest(
                id: 1,
                method: "initialize",
                params: [
                    "protocolVersion": "2025-03-26",
                    "capabilities": [:],
                    "clientInfo": [
                        "name": "Test",
                        "version": "1.0"
                    ]
                ]
            ),
            makeNotification(
                method: "notifications/initialized",
                params: [:]
            ),
            makeRequest(
                id: 2,
                method: "tools/list",
                params: [:]
            ),
            makeRequest(
                id: 3,
                method: "tools/call",
                params: [
                    "name": "project_git_branch",
                    "arguments": [:]
                ]
            ),
            makeRequest(
                id: 4,
                method: "tools/call",
                params: [
                    "name": "project_list_files",
                    "arguments": [:]
                ]
            )
        ]

        for payload in payloads {
            try writeMessage(payload, to: inputPipe.fileHandleForWriting)
        }
        inputPipe.fileHandleForWriting.closeFile()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "MCPProjectServerIntegrationTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "ProjectMCPServer завершился с ошибкой."]
            )
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    private func makeRequest(id: Int, method: String, params: [String: Any]) -> Data {
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ]
        return try! JSONSerialization.data(withJSONObject: message, options: [])
    }

    private func makeNotification(method: String, params: [String: Any]) -> Data {
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ]
        return try! JSONSerialization.data(withJSONObject: message, options: [])
    }

    private func writeMessage(_ data: Data, to handle: FileHandle) throws {
        guard let newlineData = "\n".data(using: .utf8) else {
            throw NSError(
                domain: "MCPProjectServerIntegrationTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Не удалось подготовить разделитель MCP."]
            )
        }

        handle.write(data)
        handle.write(newlineData)
    }

}

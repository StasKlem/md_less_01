import Foundation

@main
struct ProjectMCPServerMain {
    private static let protocolVersion = "2025-03-26"
    private static let serverName = "ProjectMCPServer"
    private static let serverVersion = "1.0.0"

    static func main() {
        var buffer = Data()
        let input = FileHandle.standardInput

        while true {
            let chunk = input.availableData
            if chunk.isEmpty {
                break
            }
            buffer.append(chunk)

            while let messageData = extractNextMessage(from: &buffer) {
                handleMessageData(messageData)
            }
        }
    }

    private static func handleMessageData(_ data: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: data, options: []),
            let message = object as? [String: Any],
            let method = message["method"] as? String
        else {
            return
        }

        let response: [String: Any]?
        switch method {
        case "initialize":
            response = makeInitializeResponse(id: message["id"])
        case "notifications/initialized":
            response = nil
        case "tools/list":
            response = makeToolsListResponse(id: message["id"])
        case "tools/call":
            response = makeToolCallResponse(id: message["id"], message: message)
        case "shutdown":
            response = makeEmptyResultResponse(id: message["id"])
        default:
            response = makeErrorResponse(
                id: message["id"],
                code: -32601,
                message: "Method not found"
            )
        }

        if let response {
            writeJSON(response)
        }
    }

    private static func extractNextMessage(from buffer: inout Data) -> Data? {
        guard let headerRange = buffer.range(of: Data("\r\n\r\n".utf8)) ?? buffer.range(of: Data("\n\n".utf8)) else {
            return nil
        }

        let headerData = buffer.subdata(in: buffer.startIndex..<headerRange.lowerBound)
        let headerText = String(data: headerData, encoding: .utf8) ?? ""
        let contentLength = parseContentLength(from: headerText)
        guard contentLength > 0 else {
            buffer.removeSubrange(buffer.startIndex..<headerRange.upperBound)
            return nil
        }

        let bodyStart = headerRange.upperBound
        guard buffer.count >= bodyStart + contentLength else {
            return nil
        }

        let bodyRange = bodyStart..<(bodyStart + contentLength)
        let body = buffer.subdata(in: bodyRange)
        buffer.removeSubrange(buffer.startIndex..<bodyRange.upperBound)
        return body
    }

    private static func parseContentLength(from headers: String) -> Int {
        for line in headers.split(separator: "\n") {
            let normalizedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercased = normalizedLine.lowercased()
            guard lowercased.hasPrefix("content-length:") else { continue }
            let value = normalizedLine.dropFirst("Content-Length:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(value) ?? 0
        }
        return 0
    }

    private static func makeInitializeResponse(id: Any?) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": [
                "protocolVersion": protocolVersion,
                "capabilities": [
                    "tools": [
                        "listChanged": false
                    ]
                ],
                "serverInfo": [
                    "name": serverName,
                    "version": serverVersion
                ],
                "instructions": "Используй tool project_git_branch для получения текущей git-ветки проекта."
            ]
        ]
    }

    private static func makeToolsListResponse(id: Any?) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": [
                "tools": [
                    [
                        "name": "project_git_branch",
                        "description": "Возвращает текущую git-ветку проекта.",
                        "inputSchema": [
                            "type": "object",
                            "properties": [:],
                            "additionalProperties": false
                        ],
                        "annotations": [
                            "readOnlyHint": true,
                            "openWorldHint": false
                        ]
                    ]
                ],
                "nextCursor": NSNull()
            ]
        ]
    }

    private static func makeToolCallResponse(id: Any?, message: [String: Any]) -> [String: Any] {
        let params = message["params"] as? [String: Any]
        let toolName = params?["name"] as? String ?? ""

        guard toolName == "project_git_branch" else {
            return makeErrorResponse(
                id: id,
                code: -32602,
                message: "Unknown tool"
            )
        }

        let branch = currentGitBranch()
        return [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": [
                "content": [
                    [
                        "type": "text",
                        "text": branch
                    ]
                ],
                "isError": false
            ]
        ]
    }

    private static func makeEmptyResultResponse(id: Any?) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": [:]
        ]
    }

    private static func makeErrorResponse(id: Any?, code: Int, message: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": [
                "code": code,
                "message": message
            ]
        ]
    }

    private static func currentGitBranch() -> String {
        let repositoryRoot = repositoryRootURL()

        if let branch = runGit(arguments: ["branch", "--show-current"], currentDirectoryURL: repositoryRoot), !branch.isEmpty {
            return branch
        }

        if let sha = runGit(arguments: ["rev-parse", "--short", "HEAD"], currentDirectoryURL: repositoryRoot), !sha.isEmpty {
            return "detached HEAD (\(sha))"
        }

        return "unknown"
    }

    private static func repositoryRootURL() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        if let explicitRoot = environment["PROJECT_MCP_SERVER_REPOSITORY_ROOT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !explicitRoot.isEmpty
        {
            let url = URL(fileURLWithPath: explicitRoot, isDirectory: true)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return url
            }
        }

        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return findRepositoryRoot(startingAt: currentDirectory)
    }

    private static func findRepositoryRoot(startingAt url: URL) -> URL? {
        var cursor = url
        for _ in 0...10 {
            let gitDirectory = cursor.appendingPathComponent(".git", isDirectory: true)
            if FileManager.default.fileExists(atPath: gitDirectory.path) {
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

    private static func runGit(arguments: [String], currentDirectoryURL: URL?) -> String? {
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
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text
    }

    private static func writeJSON(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: []) else {
            return
        }

        let header = "Content-Length: \(data.count)\r\n\r\n"
        FileHandle.standardOutput.write(Data(header.utf8))
        FileHandle.standardOutput.write(data)
    }
}

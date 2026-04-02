import Foundation
import XCTest
@testable import LightNeiroClient

@MainActor
final class RouterAILLMClientTaskStateTests: XCTestCase {
    func testSendEncodesTaskStateAsDedicatedSystemMessage() async throws {
        let httpClient = TaskStateCapturingHTTPClient(responseData: makeResponseData())
        let client = RouterAILLMClient(
            httpClient: httpClient,
            configuration: RouterAIConfiguration(
                endpoint: URL(string: "https://example.com/chat/completions")!,
                timeoutInterval: 30,
                apiKeyProvider: { "test-key" }
            )
        )

        let request = LLMRequest(
            systemPrompt: "You are a helpful assistant.",
            shortTermMessages: [ChatMessage(role: .user, content: "Привет")],
            workingMemory: [
                WorkingMemoryItem(
                    id: UUID(),
                    taskID: "global",
                    key: "task.goal",
                    value: "сохранить цель диалога",
                    status: .active,
                    confidence: 0.9,
                    updatedAt: Date()
                )
            ],
            longTermMemory: [],
            settings: .default,
            taskState: TaskStateMemory(
                goal: "сохранить цель диалога",
                clarifiedFacts: ["ответ нужен на русском"],
                constraints: ["не использовать SwiftUI"],
                terms: ["источник = документ"],
                updatedAt: Date()
            )
        )

        _ = try await client.send(request: request)

        let body = try XCTUnwrap(httpClient.lastRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let systemContents = messages.compactMap { item -> String? in
            guard let role = item["role"] as? String, role == "system" else { return nil }
            return item["content"] as? String
        }

        XCTAssertTrue(systemContents.contains(where: { $0.contains("TASK_STATE:") }))
        XCTAssertTrue(systemContents.contains(where: { $0.contains("goal: сохранить цель диалога") }))
        XCTAssertTrue(systemContents.contains(where: { $0.contains("не использовать SwiftUI") }))
        XCTAssertTrue(systemContents.contains(where: { $0.contains("ответ нужен на русском") }))
        XCTAssertTrue(systemContents.contains(where: { $0.contains("источник = документ") }))
    }

    func testLocalhostBackendDoesNotRequireAPIKey() async throws {
        let httpClient = TaskStateCapturingHTTPClient(responseData: makeResponseData())
        let client = RouterAILLMClient(
            httpClient: httpClient,
            configuration: RouterAIConfiguration(
                endpoint: URL(string: "http://localhost:1234/v1/chat/completions")!,
                timeoutInterval: 30,
                apiKeyProvider: { nil }
            )
        )

        _ = try await client.send(
            request: LLMRequest(
                systemPrompt: "",
                shortTermMessages: [ChatMessage(role: .user, content: "ping")],
                workingMemory: [],
                longTermMemory: [],
                settings: .default
            )
        )

        let authorizationHeader = httpClient.lastRequest?.value(forHTTPHeaderField: "Authorization")
        XCTAssertNil(authorizationHeader)
    }

    private func makeResponseData() -> Data {
        let assistantContent = #"{"answer":"ok","sources":[{"source":"/tmp/doc.md","section":"intro","chunk_id":"1"}],"quotes":[{"chunk_id":"1","source":"/tmp/doc.md","section":"intro","text":"цитата"}]}"#
        let payload: [String: Any] = [
            "choices": [
                [
                    "message": [
                        "content": assistantContent
                    ]
                ]
            ],
            "usage": [
                "prompt_tokens": 12,
                "completion_tokens": 6
            ]
        ]

        return (try? JSONSerialization.data(withJSONObject: payload, options: [])) ?? Data()
    }
}

private final class TaskStateCapturingHTTPClient: HTTPClientProtocol {
    private(set) var lastRequest: URLRequest?
    private let responseData: Data

    init(responseData: Data) {
        self.responseData = responseData
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }
}

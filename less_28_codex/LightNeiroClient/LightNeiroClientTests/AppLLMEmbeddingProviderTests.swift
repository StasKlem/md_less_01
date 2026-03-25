import Foundation
import XCTest
@testable import LightNeiroClient

@MainActor
final class AppLLMEmbeddingProviderTests: XCTestCase {
    func testLocalhostBackendDoesNotRequireAPIKeyForEmbeddings() async throws {
        let httpClient = EmbeddingCapturingHTTPClient(responseData: makeResponseData())
        let provider = AppLLMEmbeddingProvider(
            httpClient: httpClient,
            configuration: RouterAIConfiguration(
                endpoint: URL(string: "http://localhost:1234/v1/chat/completions")!,
                timeoutInterval: 30,
                apiKeyProvider: { nil }
            )
        )

        let vectors = try await provider.embed(
            texts: ["hello"],
            settings: RAGSettings(
                provider: .appLLM,
                embeddingModel: "test-embedding",
                embeddingDimension: 2,
                batchSize: 1,
                normalizeEmbeddings: false
            )
        )

        XCTAssertEqual(vectors.count, 1)
        XCTAssertNil(httpClient.lastRequest?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(httpClient.lastRequest?.url?.absoluteString, "http://localhost:1234/v1/embeddings")
    }

    private func makeResponseData() -> Data {
        let payload: [String: Any] = [
            "data": [
                [
                    "index": 0,
                    "embedding": [0.1, 0.2]
                ]
            ]
        ]
        return (try? JSONSerialization.data(withJSONObject: payload, options: [])) ?? Data()
    }
}

private final class EmbeddingCapturingHTTPClient: HTTPClientProtocol {
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

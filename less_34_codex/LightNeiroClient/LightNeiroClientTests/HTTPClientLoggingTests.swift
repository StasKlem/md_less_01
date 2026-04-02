import Foundation
import XCTest
@testable import LightNeiroClient

final class HTTPClientLoggingTests: XCTestCase {
    func testLoggingHTTPClientLogsRequestAndResponseWhenEnabled() async throws {
        let logger = RecordingHTTPRequestLogSink()
        let baseClient = StubHTTPClient(
            result: .success(
                (
                    Data(#"{"ok":true}"#.utf8),
                    HTTPURLResponse(
                        url: URL(string: "https://example.com/v1/chat/completions")!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!
                )
            )
        )
        let client = LoggingHTTPClient(baseClient: baseClient, logger: logger)

        let request = makeRequest()

        _ = try await client.data(for: request)

        XCTAssertEqual(logger.records.count, 2)
        XCTAssertTrue(logger.records[0].message.contains("📤 REQUEST"))
        XCTAssertTrue(logger.records[0].message.contains("===================="))
        XCTAssertTrue(logger.records[0].message.contains("method: POST"))
        XCTAssertTrue(logger.records[0].message.contains("url: https://example.com/v1/chat/completions"))
        XCTAssertTrue(logger.records[0].message.contains("Authorization: Bearer test-key"))
        XCTAssertTrue(logger.records[0].message.contains("--- BODY ---"))
        XCTAssertTrue(logger.records[0].message.contains(#"{"name":"Alex"}"#))
        XCTAssertTrue(logger.records[0].message.contains("body:"))

        XCTAssertTrue(logger.records[1].message.contains("📥 RESPONSE"))
        XCTAssertTrue(logger.records[1].message.contains("===================="))
        XCTAssertTrue(logger.records[1].message.contains("status: 200"))
        XCTAssertTrue(logger.records[1].message.contains("duration_ms:"))
        XCTAssertTrue(logger.records[1].message.contains("--- BODY ---"))
        XCTAssertTrue(logger.records[1].message.contains(#"{"ok":true}"#))
        XCTAssertTrue(logger.records[1].message.contains("body:"))
    }

    func testLoggingHTTPClientLogsWarningForNonSuccessStatus() async throws {
        let logger = RecordingHTTPRequestLogSink()
        let baseClient = StubHTTPClient(
            result: .success(
                (
                    Data(#"{"error":"bad"}"#.utf8),
                    HTTPURLResponse(
                        url: URL(string: "https://example.com/v1/chat/completions")!,
                        statusCode: 500,
                        httpVersion: nil,
                        headerFields: ["X-Request-ID": "abc"]
                    )!
                )
            )
        )
        let client = LoggingHTTPClient(baseClient: baseClient, logger: logger)

        _ = try await client.data(for: makeRequest())

        XCTAssertEqual(logger.records.count, 2)
        XCTAssertEqual(logger.records[1].level, .warning)
        XCTAssertTrue(logger.records[1].message.contains("📥 RESPONSE"))
        XCTAssertTrue(logger.records[1].message.contains("status: 500"))
        XCTAssertTrue(logger.records[1].message.contains("X-Request-ID: abc"))
    }

    func testLoggingHTTPClientLogsErrorWhenBaseClientThrows() async {
        let logger = RecordingHTTPRequestLogSink()
        let baseClient = StubHTTPClient(result: .failure(TestError.networkFailure))
        let client = LoggingHTTPClient(baseClient: baseClient, logger: logger)

        do {
            _ = try await client.data(for: makeRequest())
            XCTFail("Ожидалась ошибка")
        } catch {
            XCTAssertEqual(logger.records.count, 2)
            XCTAssertEqual(logger.records[1].level, .error)
            XCTAssertTrue(logger.records[1].message.contains("networkFailure"))
        }
    }

    func testMakeHTTPClientReturnsBaseClientWhenLoggingDisabled() async throws {
        let logger = RecordingHTTPRequestLogSink()
        let baseClient = StubHTTPClient(
            result: .success(
                (
                    Data(),
                    HTTPURLResponse(
                        url: URL(string: "https://example.com/disabled")!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            )
        )
        let client = makeHTTPClient(
            baseClient: baseClient,
            loggingConfiguration: .disabled,
            logger: logger
        )

        _ = try await client.data(for: makeRequest(url: URL(string: "https://example.com/disabled")!))

        XCTAssertTrue(logger.records.isEmpty)
    }

    private func makeRequest(url: URL = URL(string: "https://example.com/v1/chat/completions")!) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer test-key", forHTTPHeaderField: "Authorization")
        request.httpBody = #"{"name":"Alex"}"#.data(using: .utf8)
        return request
    }
}

private final class RecordingHTTPRequestLogSink: HTTPRequestLogSink {
    struct Record {
        let level: LogLevel
        let category: String
        let message: String
    }

    private(set) var records: [Record] = []

    func log(level: LogLevel, category: String, message: String) {
        records.append(Record(level: level, category: category, message: message))
    }
}

private final class StubHTTPClient: HTTPClientProtocol {
    enum Result {
        case success((Data, URLResponse))
        case failure(Error)
    }

    let result: Result

    init(result: Result) {
        self.result = result
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        switch result {
        case let .success(response):
            return response
        case let .failure(error):
            throw error
        }
    }
}

private enum TestError: Error {
    case networkFailure
}

extension TestError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .networkFailure:
            return "networkFailure"
        }
    }
}

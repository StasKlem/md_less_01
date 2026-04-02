import Foundation

protocol HTTPRequestLogSink {
    func log(level: LogLevel, category: String, message: String)
}

extension AppLogger: HTTPRequestLogSink {
    func log(level: LogLevel, category: String, message: String) {
        switch level {
        case .debug:
            debug(message, category: category)
        case .info:
            info(message, category: category)
        case .warning:
            warning(message, category: category)
        case .error:
            error(message, category: category)
        }
    }
}

struct HTTPClientLoggingConfiguration: Sendable {
    let isEnabled: Bool

    static let disabled = HTTPClientLoggingConfiguration(isEnabled: false)

    static var live: HTTPClientLoggingConfiguration {
        HTTPClientLoggingConfiguration(
            isEnabled: ProcessInfo.processInfo.environment["LIGHTNEIRO_HTTP_LOGGING"]?.isEnabledFlag ?? false
        )
    }
}

func makeHTTPClient(
    baseClient: HTTPClientProtocol = URLSession.shared,
    loggingConfiguration: HTTPClientLoggingConfiguration = .live,
    logger: HTTPRequestLogSink = AppLogger.shared
) -> HTTPClientProtocol {
    guard loggingConfiguration.isEnabled else {
        return baseClient
    }
    return LoggingHTTPClient(baseClient: baseClient, logger: logger)
}

final class LoggingHTTPClient: HTTPClientProtocol {
    private let baseClient: HTTPClientProtocol
    private let logger: HTTPRequestLogSink
    private let formatter = HTTPRequestLogFormatter()

    init(
        baseClient: HTTPClientProtocol,
        logger: HTTPRequestLogSink = AppLogger.shared
    ) {
        self.baseClient = baseClient
        self.logger = logger
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let startedAt = Date()
        logger.log(
            level: .info,
            category: "network.http",
            message: formatter.requestMessage(for: request)
        )

        do {
            let result = try await baseClient.data(for: request)
            let durationMs = Self.durationMs(since: startedAt)

            if let httpResponse = result.1 as? HTTPURLResponse {
                let responseLevel: LogLevel = (200...299).contains(httpResponse.statusCode) ? .info : .warning
                logger.log(
                    level: responseLevel,
                    category: "network.http",
                    message: formatter.responseMessage(
                        for: httpResponse,
                        data: result.0,
                        durationMs: durationMs
                    )
                )
            } else {
                logger.log(
                    level: .warning,
                    category: "network.http",
                    message: formatter.nonHTTPResponseMessage(
                        request: request,
                        response: result.1,
                        durationMs: durationMs
                    )
                )
            }

            return result
        } catch {
            let durationMs = Self.durationMs(since: startedAt)
            logger.log(
                level: .error,
                category: "network.http",
                message: formatter.failureMessage(
                    for: request,
                    error: error,
                    durationMs: durationMs
                )
            )
            throw error
        }
    }

    private static func durationMs(since startedAt: Date) -> Int {
        Int(Date().timeIntervalSince(startedAt) * 1000.0)
    }
}

struct HTTPRequestLogFormatter {
    func requestMessage(for request: URLRequest) -> String {
        var lines: [String] = [
            "====================",
            "📤 REQUEST",
            "====================",
            "method: \(request.httpMethod ?? "GET")",
            "url: \(request.url?.absoluteString ?? "<no-url>")",
            "",
            "headers:"
        ]

        lines.append(contentsOf: formattedHeaders(from: request.allHTTPHeaderFields))
        lines.append("")
        lines.append("--- BODY ---")
        lines.append("body:")
        lines.append(formattedBody(from: request.httpBody))
        lines.append("====================")
        return lines.joined(separator: "\n")
    }

    func responseMessage(for response: HTTPURLResponse, data: Data, durationMs: Int) -> String {
        var lines: [String] = [
            "====================",
            "📥 RESPONSE",
            "====================",
            "status: \(response.statusCode)",
            "url: \(response.url?.absoluteString ?? "<no-url>")",
            "duration_ms: \(durationMs)",
            "",
            "headers:"
        ]

        lines.append(contentsOf: formattedHeaders(from: response.allHeaderFields))
        lines.append("")
        lines.append("--- BODY ---")
        lines.append("body:")
        lines.append(formattedBody(from: data))
        lines.append("====================")
        return lines.joined(separator: "\n")
    }

    func nonHTTPResponseMessage(request: URLRequest, response: URLResponse, durationMs: Int) -> String {
        [
            "====================",
            "📥 RESPONSE",
            "====================",
            "status: <non-http>",
            "url: \(request.url?.absoluteString ?? "<no-url>")",
            "duration_ms: \(durationMs)",
            "details: \(String(describing: response))",
            "===================="
        ]
        .joined(separator: "\n")
    }

    func failureMessage(for request: URLRequest, error: Error, durationMs: Int) -> String {
        [
            "====================",
            "📤 REQUEST",
            "====================",
            "method: \(request.httpMethod ?? "GET")",
            "url: \(request.url?.absoluteString ?? "<no-url>")",
            "duration_ms: \(durationMs)",
            "error: \(error.localizedDescription)",
            "===================="
        ]
        .joined(separator: "\n")
    }

    private func formattedHeaders(from headers: [String: String]?) -> [String] {
        guard let headers, !headers.isEmpty else {
            return ["<empty>"]
        }

        return headers
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { "\($0.key): \($0.value)" }
    }

    private func formattedHeaders(from headers: [AnyHashable: Any]) -> [String] {
        guard !headers.isEmpty else {
            return ["<empty>"]
        }

        return headers
            .map { "\($0.key): \($0.value)" }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func formattedBody(from data: Data?) -> String {
        guard let data, !data.isEmpty else {
            return "<empty>"
        }

        if let text = String(data: data, encoding: .utf8) {
            return text
        }

        return "<binary \(data.count) bytes>\n\(data.base64EncodedString())"
    }
}

private extension String {
    var isEnabledFlag: Bool {
        let normalized = trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["1", "true", "yes", "on"].contains(normalized)
    }
}

import Foundation

protocol HTTPClient: Sendable {
    func get(url: URL) async throws -> Data
}

struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession
    private let logger: Logger?

    init(
        session: URLSession = .shared,
        logger: Logger? = nil
    ) {
        self.session = session
        self.logger = logger
    }

    func get(url: URL) async throws -> Data {
        logger?.debug("HTTP GET \(url.absoluteString)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HackerNewsToolError.upstreamFailure("Invalid HTTP response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let bodyPreview = String(data: data, encoding: .utf8)?.prefix(300) ?? ""
            logger?.warn("HTTP \(httpResponse.statusCode) for \(url.absoluteString)")
            throw HackerNewsToolError.upstreamFailure(
                "HTTP \(httpResponse.statusCode). \(bodyPreview)"
            )
        }

        logger?.debug("HTTP \(httpResponse.statusCode) for \(url.absoluteString)")
        return data
    }
}

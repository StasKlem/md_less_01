import Foundation

protocol HTTPClient: Sendable {
    func get(url: URL) async throws -> Data
}

struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func get(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenWeatherToolError.upstreamFailure("Invalid HTTP response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let bodyPreview = String(data: data, encoding: .utf8)?.prefix(300) ?? ""
            throw OpenWeatherToolError.upstreamFailure(
                "HTTP \(httpResponse.statusCode). \(bodyPreview)"
            )
        }
        return data
    }
}

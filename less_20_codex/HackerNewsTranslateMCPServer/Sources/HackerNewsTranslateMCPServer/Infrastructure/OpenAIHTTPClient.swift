import Foundation

protocol OpenAIHTTPClient: Sendable {
    func postJSON<T: Encodable>(url: URL, bearerToken: String, body: T) async throws -> Data
}

struct URLSessionOpenAIHTTPClient: OpenAIHTTPClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func postJSON<T: Encodable>(url: URL, bearerToken: String, body: T) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HackerNewsTranslateToolError.llmFailure("Invalid HTTP response.")
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let bodyPreview = String(data: data, encoding: .utf8)?.prefix(500) ?? ""
            throw HackerNewsTranslateToolError.llmFailure(
                "HTTP \(httpResponse.statusCode): \(bodyPreview)"
            )
        }

        return data
    }
}

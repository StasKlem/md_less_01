import Foundation

struct AppLLMEmbeddingProvider: EmbeddingProvider {
    private let httpClient: HTTPClientProtocol
    private let configuration: RouterAIConfiguration
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        httpClient: HTTPClientProtocol = URLSession.shared,
        configuration: RouterAIConfiguration = .default
    ) {
        self.httpClient = httpClient
        self.configuration = configuration
    }

    func embed(texts: [String], settings: RAGSettings) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        guard let apiKey = configuration.apiKeyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            throw RAGError.embeddingProviderUnavailable("Missing API key for app embedding provider")
        }

        var urlRequest = URLRequest(url: embeddingEndpoint(from: configuration.endpoint))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = configuration.timeoutInterval
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try encoder.encode(EmbeddingRequest(model: settings.embeddingModel, input: texts))

        let (data, response) = try await httpClient.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RouterAILLMClientError.invalidHTTPResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw RouterAILLMClientError.api(
                statusCode: httpResponse.statusCode,
                message: String(data: data, encoding: .utf8) ?? "Unknown API error"
            )
        }

        let payload = try decoder.decode(EmbeddingResponse.self, from: data)
        let vectors = payload.data.sorted(by: { $0.index < $1.index }).map(\.embedding)

        return settings.normalizeEmbeddings ? vectors.map(normalize(vector:)) : vectors
    }

    private func embeddingEndpoint(from completionEndpoint: URL) -> URL {
        var components = URLComponents(url: completionEndpoint, resolvingAgainstBaseURL: false)
        let completionSuffix = "/chat/completions"
        if let path = components?.path, path.hasSuffix(completionSuffix) {
            let basePath = String(path.dropLast(completionSuffix.count))
            components?.path = basePath + "/embeddings"
            return components?.url ?? completionEndpoint
        }
        return completionEndpoint
    }

    private func normalize(vector: [Float]) -> [Float] {
        let normSquared = vector.reduce(Float(0)) { partial, value in partial + value * value }
        let norm = sqrt(normSquared)
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }
}

struct LocalONNXEmbeddingProvider: EmbeddingProvider {
    func embed(texts: [String], settings: RAGSettings) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        throw RAGError.embeddingProviderUnavailable(
            "ONNX runtime integration is not configured in this target. Provide a concrete ONNX adapter."
        )
    }
}

struct DeterministicHashEmbeddingProvider: EmbeddingProvider {
    private let dimension: Int

    init(dimension: Int = 64) {
        self.dimension = dimension
    }

    func embed(texts: [String], settings: RAGSettings) async throws -> [[Float]] {
        texts.map { text in
            var vector = Array(repeating: Float(0), count: max(8, dimension))
            for (index, scalar) in text.unicodeScalars.enumerated() {
                let bucket = (Int(scalar.value) + index) % vector.count
                vector[bucket] += 1.0
            }

            if settings.normalizeEmbeddings {
                let normSquared = vector.reduce(Float(0)) { partial, value in partial + value * value }
                let norm = sqrt(normSquared)
                if norm > 0 {
                    return vector.map { $0 / norm }
                }
            }
            return vector
        }
    }
}

private struct EmbeddingRequest: Encodable {
    let model: String
    let input: [String]
}

private struct EmbeddingResponse: Decodable {
    let data: [EmbeddingRow]

    struct EmbeddingRow: Decodable {
        let index: Int
        let embedding: [Float]
    }
}

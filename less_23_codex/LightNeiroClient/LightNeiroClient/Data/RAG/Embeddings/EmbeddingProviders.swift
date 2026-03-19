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

        let endpoint = try embeddingEndpoint(from: configuration.endpoint)
        let batchSize = max(1, settings.batchSize)
        AppLogger.shared.info(
            "Старт запроса эмбеддингов: endpoint=\(endpoint.absoluteString), model=\(settings.embeddingModel), texts=\(texts.count), batchSize=\(batchSize), normalize=\(settings.normalizeEmbeddings)",
            category: "rag.embedding"
        )
        var vectors: [[Float]] = []
        vectors.reserveCapacity(texts.count)
        var batchStart = 0
        while batchStart < texts.count {
            let batchEnd = min(batchStart + batchSize, texts.count)
            let batchTexts = Array(texts[batchStart..<batchEnd])
            AppLogger.shared.debug(
                "Отправка батча на эмбеддинг: range=\(batchStart)..<\(batchEnd), total=\(texts.count)",
                category: "rag.embedding"
            )
            let request = try makeRequest(endpoint: endpoint, apiKey: apiKey, model: settings.embeddingModel, input: batchTexts)
            let (data, response) = try await httpClient.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw RouterAILLMClientError.invalidHTTPResponse
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                let responseText = String(data: data, encoding: .utf8) ?? "Unknown API error"
                AppLogger.shared.warning(
                    "Ошибка запроса эмбеддингов: status=\(httpResponse.statusCode), endpoint=\(endpoint.absoluteString), model=\(settings.embeddingModel), range=\(batchStart)..<\(batchEnd), response=\(responseText)",
                    category: "rag.embedding"
                )
                throw RouterAILLMClientError.api(
                    statusCode: httpResponse.statusCode,
                    message: responseText
                )
            }

            let payload = try decoder.decode(EmbeddingResponse.self, from: data)
            let currentVectors = payload.data.sorted(by: { $0.index < $1.index }).map(\.embedding)
            try validateEmbeddings(currentVectors, expectedTextCount: batchTexts.count, settings: settings)
            vectors.append(contentsOf: currentVectors)
            AppLogger.shared.debug(
                "Эмбеддинг батча получен: range=\(batchStart)..<\(batchEnd), vectors=\(currentVectors.count)",
                category: "rag.embedding"
            )
            batchStart = batchEnd
        }

        let firstDimension = vectors.first?.count ?? 0
        AppLogger.shared.info(
            "Ответ эмбеддингов получен: vectors=\(vectors.count), dimension=\(firstDimension), model=\(settings.embeddingModel)",
            category: "rag.embedding"
        )

        return settings.normalizeEmbeddings ? vectors.map(normalize(vector:)) : vectors
    }

    private func embeddingEndpoint(from completionEndpoint: URL) throws -> URL {
        var components = URLComponents(url: completionEndpoint, resolvingAgainstBaseURL: false)
        if components?.path.hasSuffix("/embeddings") == true {
            return completionEndpoint
        }
        let completionSuffix = "/chat/completions"
        if let path = components?.path, path.hasSuffix(completionSuffix) {
            let basePath = String(path.dropLast(completionSuffix.count))
            components?.path = basePath + "/embeddings"
            return components?.url ?? completionEndpoint
        }
        throw RAGError.embeddingProviderUnavailable(
            "Unsupported embeddings endpoint path: \(completionEndpoint.absoluteString). Expected suffix /chat/completions or /embeddings."
        )
    }

    private func makeRequest(endpoint: URL, apiKey: String, model: String, input: [String]) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(
            EmbeddingRequest(
                model: model,
                input: input,
                encodingFormat: .float
            )
        )
        return request
    }

    private func normalize(vector: [Float]) -> [Float] {
        let normSquared = vector.reduce(Float(0)) { partial, value in partial + value * value }
        let norm = sqrt(normSquared)
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }

    private func validateEmbeddings(_ vectors: [[Float]], expectedTextCount: Int, settings: RAGSettings) throws {
        guard vectors.count == expectedTextCount else {
            throw RAGError.invalidEmbeddingDimension(expected: expectedTextCount, actual: vectors.count)
        }

        guard let first = vectors.first else { return }
        if first.count != settings.embeddingDimension {
            throw RAGError.invalidEmbeddingDimension(expected: settings.embeddingDimension, actual: first.count)
        }

        if let mismatched = vectors.first(where: { $0.count != first.count }) {
            throw RAGError.invalidEmbeddingDimension(expected: first.count, actual: mismatched.count)
        }
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
    enum EncodingFormat: String, Encodable {
        case float
        case base64
    }

    let model: String
    let input: [String]
    let encodingFormat: EncodingFormat

    private enum CodingKeys: String, CodingKey {
        case model
        case input
        case encodingFormat = "encoding_format"
    }
}

private struct EmbeddingResponse: Decodable {
    let data: [EmbeddingRow]

    struct EmbeddingRow: Decodable {
        let index: Int
        let embedding: [Float]
    }
}

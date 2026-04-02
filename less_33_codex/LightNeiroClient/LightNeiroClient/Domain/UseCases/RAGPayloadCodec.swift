import Foundation

protocol RAGPayloadCoding {
    /// Формирует payload, когда релевантных данных для уверенного ответа не хватает.
    func makeNeedsClarificationPayloadJSON() -> String

    /// Проверяет RAG-payload и возвращает нормализованный JSON.
    func finalizeRAGResponseContent(rawContent: String, retrieval: [SearchResult]) throws -> String
}

enum RAGPayloadCodecFactory {
    /// Создает кодек RAG JSON-контракта.
    static func make() -> RAGPayloadCoding {
        RAGPayloadCodec()
    }
}

enum RAGPayloadCodecError: LocalizedError {
    case invalidJSON
    case invalidContract

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "LLM вернул невалидный JSON для RAG-ответа."
        case .invalidContract:
            return "LLM вернул JSON, который нарушает контракт RAG-ответа."
        }
    }
}

fileprivate final class RAGPayloadCodec: RAGPayloadCoding {
    private let decoder = JSONDecoder()
    private let noMatchesChunkID = "00000000-0000-0000-0000-000000000000"

    func makeNeedsClarificationPayloadJSON() -> String {
        let payload = makeNoMatchesPayload(answer: "не знаю. Пожалуйста, уточните вопрос.")
        return encodeRAGPayload(payload)
    }

    func finalizeRAGResponseContent(rawContent: String, retrieval _: [SearchResult]) throws -> String {
        guard let decoded = decodeRAGPayload(from: rawContent) else {
            throw RAGPayloadCodecError.invalidJSON
        }
        guard isValidRAGPayload(decoded, requireEvidence: true) else {
            throw RAGPayloadCodecError.invalidContract
        }
        return encodeRAGPayload(decoded)
    }

    private func decodeRAGPayload(from rawContent: String) -> RAGResponsePayload? {
        guard let cleaned = JSONContentExtractor.extractJSONObject(from: rawContent),
              let data = cleaned.data(using: .utf8) else { return nil }
        return try? decoder.decode(RAGResponsePayload.self, from: data)
    }

    private func isValidRAGPayload(_ payload: RAGResponsePayload, requireEvidence: Bool) -> Bool {
        guard !payload.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        if !requireEvidence {
            return true
        }

        guard !payload.sources.isEmpty, !payload.quotes.isEmpty else {
            return false
        }

        let sourceChunkIDs = Set(payload.sources.map(\.chunkID))
        guard !sourceChunkIDs.isEmpty else {
            return false
        }

        for source in payload.sources {
            if source.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
            if source.chunkID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
        }

        for quote in payload.quotes {
            if quote.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
            if !sourceChunkIDs.contains(quote.chunkID) {
                return false
            }
        }

        return true
    }

    private func encodeRAGPayload(_ payload: RAGResponsePayload) -> String {
        let encoder = JSONEncoder()
        if #available(macOS 10.13, *) {
            encoder.outputFormatting = [.sortedKeys]
        }

        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"answer":"не знаю. Пожалуйста, уточните вопрос.","sources":[],"quotes":[]}"#
        }
        return json
    }

    private func makeNoMatchesPayload(answer: String) -> RAGResponsePayload {
        let source = RAGSourceItem(
            source: "rag://no-matches",
            section: "retrieval",
            chunkID: noMatchesChunkID
        )
        let quote = RAGQuoteItem(
            chunkID: noMatchesChunkID,
            source: "rag://no-matches",
            section: "retrieval",
            text: "Релевантный контекст в базе не найден."
        )
        return RAGResponsePayload(answer: answer, sources: [source], quotes: [quote])
    }
}

private struct RAGResponsePayload: Codable, Equatable {
    let answer: String
    let sources: [RAGSourceItem]
    let quotes: [RAGQuoteItem]
}

private struct RAGSourceItem: Codable, Equatable {
    let source: String
    let section: String?
    let chunkID: String

    private enum CodingKeys: String, CodingKey {
        case source
        case section
        case chunkID = "chunk_id"
    }
}

private struct RAGQuoteItem: Codable, Equatable {
    let chunkID: String
    let source: String
    let section: String?
    let text: String

    private enum CodingKeys: String, CodingKey {
        case chunkID = "chunk_id"
        case source
        case section
        case text
    }
}

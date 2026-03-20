import Foundation

protocol RAGPayloadCoding {
    /// Формирует payload, когда релевантных данных для уверенного ответа не хватает.
    func makeNeedsClarificationPayloadJSON() -> String

    /// Проверяет и при необходимости чинит RAG-пayload, чтобы соблюсти контракт ответа.
    func finalizeRAGResponseContent(rawContent: String, retrieval: [SearchResult]) -> String
}

enum RAGPayloadCodecFactory {
    /// Создает кодек RAG JSON-контракта.
    static func make() -> RAGPayloadCoding {
        RAGPayloadCodec()
    }
}

fileprivate final class RAGPayloadCodec: RAGPayloadCoding {
    private let decoder = JSONDecoder()

    func makeNeedsClarificationPayloadJSON() -> String {
        let payload = RAGResponsePayload(
            answer: "не знаю. Пожалуйста, уточните вопрос.",
            sources: [],
            quotes: []
        )
        return encodeRAGPayload(payload)
    }

    func finalizeRAGResponseContent(rawContent: String, retrieval: [SearchResult]) -> String {
        if let decoded = decodeRAGPayload(from: rawContent), isValidRAGPayload(decoded, requireEvidence: true) {
            return encodeRAGPayload(decoded)
        }

        let repaired = repairRAGPayload(from: rawContent, retrieval: retrieval)
        return encodeRAGPayload(repaired)
    }

    private func decodeRAGPayload(from rawContent: String) -> RAGResponsePayload? {
        let cleaned = rawContent
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else { return nil }
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

    private func repairRAGPayload(from rawContent: String, retrieval: [SearchResult]) -> RAGResponsePayload {
        var seenChunkIDs = Set<String>()
        var sources: [RAGSourceItem] = []

        for result in retrieval {
            let chunkID = result.chunk.id.uuidString
            guard seenChunkIDs.insert(chunkID).inserted else { continue }
            sources.append(
                RAGSourceItem(
                    source: result.chunk.source,
                    section: result.chunk.section,
                    chunkID: chunkID
                )
            )
        }

        let quotes: [RAGQuoteItem] = retrieval.prefix(3).map { result in
            RAGQuoteItem(
                chunkID: result.chunk.id.uuidString,
                source: result.chunk.source,
                section: result.chunk.section,
                text: normalizedQuoteText(result.chunk.content)
            )
        }

        let fallbackAnswer = makeFallbackRAGAnswer(rawContent: rawContent, quotes: quotes)
        return RAGResponsePayload(
            answer: fallbackAnswer,
            sources: sources,
            quotes: quotes
        )
    }

    private func makeFallbackRAGAnswer(rawContent: String, quotes: [RAGQuoteItem]) -> String {
        let candidate = rawContent
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !candidate.isEmpty, !candidate.hasPrefix("{"), !candidate.hasPrefix("[") {
            return String(candidate.prefix(280))
        }

        guard let firstQuote = quotes.first?.text, !firstQuote.isEmpty else {
            return "Ответ сформирован на основе найденных источников."
        }
        return "Согласно найденным источникам: \(String(firstQuote.prefix(240)))"
    }

    private func normalizedQuoteText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

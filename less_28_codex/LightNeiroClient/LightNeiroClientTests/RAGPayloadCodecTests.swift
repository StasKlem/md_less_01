import XCTest
@testable import LightNeiroClient

final class RAGPayloadCodecTests: XCTestCase {
    func testFinalizeRAGResponseContentPreservesValidPayload() throws {
        let codec = RAGPayloadCodecFactory.make()
        let chunkID = UUID().uuidString
        let rawContent = """
        {
          "answer": "Готовый ответ",
          "sources": [{"source":"/tmp/doc.md","section":"intro","chunk_id":"\(chunkID)"}],
          "quotes": [{"chunk_id":"\(chunkID)","source":"/tmp/doc.md","section":"intro","text":"цитата"}]
        }
        """

        let finalized = try codec.finalizeRAGResponseContent(rawContent: rawContent, retrieval: [])
        let payload = try? decodePayload(from: finalized)

        XCTAssertEqual(payload?.answer, "Готовый ответ")
        XCTAssertEqual(payload?.sources.count, 1)
        XCTAssertEqual(payload?.quotes.count, 1)
        XCTAssertEqual(payload?.sources.first?.chunkID, chunkID)
        XCTAssertEqual(payload?.quotes.first?.chunkID, chunkID)
    }

    func testFinalizeRAGResponseContentExtractsPayloadFromFencedBlockWithPreambleAndPostamble() throws {
        let codec = RAGPayloadCodecFactory.make()
        let chunkID = UUID().uuidString
        let rawContent = """
        Вот ответ в нужном формате:
        ```json
        {
          "answer": "Готовый ответ",
          "sources": [{"source":"/tmp/doc.md","section":"intro","chunk_id":"\(chunkID)"}],
          "quotes": [{"chunk_id":"\(chunkID)","source":"/tmp/doc.md","section":"intro","text":"цитата"}]
        }
        ```
        Спасибо.
        """

        let finalized = try codec.finalizeRAGResponseContent(rawContent: rawContent, retrieval: [])
        let payload = try? decodePayload(from: finalized)

        XCTAssertEqual(payload?.answer, "Готовый ответ")
        XCTAssertEqual(payload?.sources.first?.chunkID, chunkID)
        XCTAssertEqual(payload?.quotes.first?.chunkID, chunkID)
    }

    func testFinalizeRAGResponseContentExtractsPayloadFromWrappedJSONObject() throws {
        let codec = RAGPayloadCodecFactory.make()
        let chunkID = UUID().uuidString
        let rawContent = """
        Ответ:
        {"answer":"Готовый ответ","sources":[{"source":"/tmp/doc.md","section":"intro","chunk_id":"\(chunkID)"}],"quotes":[{"chunk_id":"\(chunkID)","source":"/tmp/doc.md","section":"intro","text":"цитата"}]}
        Конец.
        """

        let finalized = try codec.finalizeRAGResponseContent(rawContent: rawContent, retrieval: [])
        let payload = try? decodePayload(from: finalized)

        XCTAssertEqual(payload?.answer, "Готовый ответ")
        XCTAssertEqual(payload?.sources.first?.chunkID, chunkID)
        XCTAssertEqual(payload?.quotes.first?.chunkID, chunkID)
    }

    func testFinalizeRAGResponseContentThrowsForInvalidPayload() {
        let codec = RAGPayloadCodecFactory.make()
        let retrieval = [
            Self.makeSearchResult(content: "Первая строка\nиз источника.", score: 0.92, section: "s1"),
            Self.makeSearchResult(content: "Вторая строка.", score: 0.88, section: "s2")
        ]

        XCTAssertThrowsError(
            try codec.finalizeRAGResponseContent(rawContent: "{invalid-json", retrieval: retrieval)
        ) { error in
            XCTAssertEqual(error.localizedDescription, "LLM вернул невалидный JSON для RAG-ответа.")
        }
    }

    func testMakeNeedsClarificationPayloadJSONReturnsExpectedFallbackPayload() {
        let codec = RAGPayloadCodecFactory.make()

        let json = codec.makeNeedsClarificationPayloadJSON()
        let payload = try? decodePayload(from: json)

        XCTAssertTrue((payload?.answer.lowercased().contains("не знаю")) ?? false)
        XCTAssertTrue((payload?.answer.lowercased().contains("уточните")) ?? false)
        XCTAssertEqual(payload?.sources.count, 1)
        XCTAssertEqual(payload?.quotes.count, 1)
        XCTAssertEqual(payload?.sources.first?.source, "rag://no-matches")
        XCTAssertEqual(payload?.quotes.first?.source, "rag://no-matches")
    }

    private func decodePayload(from json: String) throws -> TestRAGPayload {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try JSONDecoder().decode(TestRAGPayload.self, from: data)
    }

    private static func makeSearchResult(content: String, score: Float, section: String) -> SearchResult {
        let chunk = DocumentChunk(
            id: UUID(),
            content: content,
            embedding: [0, 1, 0],
            source: "/tmp/doc.md",
            title: "doc",
            section: section,
            offset: 0
        )
        return SearchResult(chunk: chunk, score: score)
    }
}

private struct TestRAGPayload: Decodable {
    let answer: String
    let sources: [TestRAGSource]
    let quotes: [TestRAGQuote]
}

private struct TestRAGSource: Decodable {
    let source: String
    let section: String?
    let chunkID: String

    private enum CodingKeys: String, CodingKey {
        case source
        case section
        case chunkID = "chunk_id"
    }
}

private struct TestRAGQuote: Decodable {
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

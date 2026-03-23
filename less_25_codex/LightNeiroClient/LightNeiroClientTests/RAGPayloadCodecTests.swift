import XCTest
@testable import LightNeiroClient

final class RAGPayloadCodecTests: XCTestCase {
    func testFinalizeRAGResponseContentPreservesValidPayload() {
        let codec = RAGPayloadCodecFactory.make()
        let chunkID = UUID().uuidString
        let rawContent = """
        {
          "answer": "Готовый ответ",
          "sources": [{"source":"/tmp/doc.md","section":"intro","chunk_id":"\(chunkID)"}],
          "quotes": [{"chunk_id":"\(chunkID)","source":"/tmp/doc.md","section":"intro","text":"цитата"}]
        }
        """

        let finalized = codec.finalizeRAGResponseContent(rawContent: rawContent, retrieval: [])
        let payload = try? decodePayload(from: finalized)

        XCTAssertEqual(payload?.answer, "Готовый ответ")
        XCTAssertEqual(payload?.sources.count, 1)
        XCTAssertEqual(payload?.quotes.count, 1)
        XCTAssertEqual(payload?.sources.first?.chunkID, chunkID)
        XCTAssertEqual(payload?.quotes.first?.chunkID, chunkID)
    }

    func testFinalizeRAGResponseContentRepairsInvalidPayloadUsingRetrieval() {
        let codec = RAGPayloadCodecFactory.make()
        let retrieval = [
            Self.makeSearchResult(content: "Первая строка\nиз источника.", score: 0.92, section: "s1"),
            Self.makeSearchResult(content: "Вторая строка.", score: 0.88, section: "s2")
        ]

        let finalized = codec.finalizeRAGResponseContent(rawContent: "{invalid-json", retrieval: retrieval)
        let payload = try? decodePayload(from: finalized)

        XCTAssertFalse((payload?.sources.isEmpty) ?? true)
        XCTAssertFalse((payload?.quotes.isEmpty) ?? true)

        let sourceChunkIDs = Set(payload?.sources.map(\.chunkID) ?? [])
        XCTAssertTrue((payload?.quotes.allSatisfy { sourceChunkIDs.contains($0.chunkID) }) ?? false)
        XCTAssertFalse((payload?.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ?? true)
    }

    func testMakeNeedsClarificationPayloadJSONReturnsExpectedFallbackPayload() {
        let codec = RAGPayloadCodecFactory.make()

        let json = codec.makeNeedsClarificationPayloadJSON()
        let payload = try? decodePayload(from: json)

        XCTAssertTrue((payload?.answer.lowercased().contains("не знаю")) ?? false)
        XCTAssertTrue((payload?.answer.lowercased().contains("уточните")) ?? false)
        XCTAssertEqual(payload?.sources.count, 0)
        XCTAssertEqual(payload?.quotes.count, 0)
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

import XCTest
@testable import LightNeiroClient

final class RAGResponseDisplayFormatterTests: XCTestCase {
    func testFormatBuildsAnswerAndSourceQuoteBlocksForAssistantJSON() {
        let formatter = RAGResponseDisplayFormatter()
        let json = """
        {
          "answer": "Готовый ответ по данным контекста.",
          "sources": [
            { "source": "/tmp/a.md", "section": "intro", "chunk_id": "1" },
            { "source": "/tmp/b.md", "section": null, "chunk_id": "2" }
          ],
          "quotes": [
            { "chunk_id": "1", "source": "/tmp/a.md", "section": "intro", "text": "Первая цитата" },
            { "chunk_id": "2", "source": "/tmp/b.md", "section": null, "text": "Вторая цитата" }
          ]
        }
        """

        let result = formatter.format(role: .assistant, content: json)

        XCTAssertEqual(
            result,
            """
            Готовый ответ по данным контекста.

            источник : /tmp/a.md — intro
            Первая цитата

            источник : /tmp/b.md
            Вторая цитата
            """
        )
    }

    func testFormatIgnoresDuplicateSourceChunkIDsWithoutCrashing() {
        let formatter = RAGResponseDisplayFormatter()
        let json = """
        {
          "answer": "Готовый ответ по данным контекста.",
          "sources": [
            { "source": "/tmp/a.md", "section": "intro", "chunk_id": "1" },
            { "source": "/tmp/a-duplicate.md", "section": "duplicate", "chunk_id": "1" }
          ],
          "quotes": [
            { "chunk_id": "1", "source": "/tmp/a.md", "section": "intro", "text": "Первая цитата" }
          ]
        }
        """

        let result = formatter.format(role: .assistant, content: json)

        XCTAssertEqual(
            result,
            """
            Готовый ответ по данным контекста.

            источник : /tmp/a.md — intro
            Первая цитата
            """
        )
    }

    func testFormatReturnsRawContentForNonJSONAssistantMessage() {
        let formatter = RAGResponseDisplayFormatter()
        let content = "Обычный ответ без JSON."

        let result = formatter.format(role: .assistant, content: content)

        XCTAssertEqual(result, content)
    }

    func testFormatReturnsRawContentForUserRole() {
        let formatter = RAGResponseDisplayFormatter()
        let json = #"{"answer":"Ответ","sources":[],"quotes":[]}"#

        let result = formatter.format(role: .user, content: json)

        XCTAssertEqual(result, json)
    }
}

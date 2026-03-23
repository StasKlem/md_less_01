import Testing
@testable import HackerNewsTranslateMCPServer

struct HackerNewsStoryInputParserTests {
    @Test
    func parseStoryExtractsFields() throws {
        let parser = HackerNewsStoryInputParser()
        let story = try parser.parse(
            """
            Random Hacker News story:
            - Title: Ship Swift 6
            - ID: 101
            - Author: alice
            - Score: 99
            - Time: 2026-03-13 10:00 UTC
            - URL: https://example.com/story
            """
        )

        #expect(story.title == "Ship Swift 6")
        #expect(story.id == 101)
        #expect(story.author == "alice")
        #expect(story.score == 99)
        #expect(story.url == "https://example.com/story")
    }

    @Test
    func parseStoryFailsWithoutTitle() {
        let parser = HackerNewsStoryInputParser()

        #expect(throws: HackerNewsTranslateToolError.self) {
            _ = try parser.parse(
                """
                Random Hacker News story:
                - ID: 101
                - URL: https://example.com/story
                """
            )
        }
    }
}

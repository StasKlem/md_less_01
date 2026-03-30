import Testing
@testable import HackerNewsSummaryMCPServer

struct HackerNewsStoryInputParserTests {
    @Test
    func parseStoryExtractsFields() throws {
        let parser = HackerNewsStoryInputParser()
        let stories = try parser.parseMany([
            """
            Random Hacker News story:
            - Title: Ship Swift 6
            - ID: 101
            - Author: alice
            - Score: 99
            - Time: 2026-03-13 10:00 UTC
            - URL: https://example.com/story
            """
        ])

        #expect(stories.count == 1)
        #expect(stories[0].title == "Ship Swift 6")
        #expect(stories[0].id == 101)
        #expect(stories[0].author == "alice")
        #expect(stories[0].score == 99)
        #expect(stories[0].url == "https://example.com/story")
    }

    @Test
    func parseStoryFailsWithoutTitle() {
        let parser = HackerNewsStoryInputParser()

        #expect(throws: HackerNewsSummaryToolError.self) {
            _ = try parser.parseMany([
                """
                Random Hacker News story:
                - ID: 101
                - URL: https://example.com/story
                """
            ])
        }
    }
}

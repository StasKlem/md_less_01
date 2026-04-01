import MCP
import Testing
@testable import HackerNewsSummaryMCPServer

struct HackerNewsSummaryToolServiceTests {
    @Test
    func summarizeToolReturnsLLMResponse() async {
        let service = HackerNewsSummaryToolService(
            summarizeUseCase: SummarizeHackerNewsStoriesUseCase(repository: StubRepository())
        )

        let result = await service.callTool(
            name: HackerNewsSummaryToolCatalog.summarizeToolName,
            arguments: [
                "stories": [
                    "Random Hacker News story:\n- Title: Ship Swift 6\n- ID: 101\n- Author: alice\n- URL: https://example.com/1"
                ]
            ]
        )

        #expect(result.isError == false)
        #expect(extractText(result).contains("Summary for 1 stories"))
    }

    @Test
    func summarizeToolRejectsMissingStories() async {
        let service = HackerNewsSummaryToolService(
            summarizeUseCase: SummarizeHackerNewsStoriesUseCase(repository: StubRepository())
        )

        let result = await service.callTool(
            name: HackerNewsSummaryToolCatalog.summarizeToolName,
            arguments: [:]
        )

        #expect(result.isError == true)
        #expect(extractText(result).contains("Argument 'stories'"))
    }

    @Test
    func summarizeToolRejectsInvalidStoryFormat() async {
        let service = HackerNewsSummaryToolService(
            summarizeUseCase: SummarizeHackerNewsStoriesUseCase(repository: StubRepository())
        )

        let result = await service.callTool(
            name: HackerNewsSummaryToolCatalog.summarizeToolName,
            arguments: ["stories": ["bad format"]]
        )

        #expect(result.isError == true)
        #expect(extractText(result).contains("Could not parse story"))
    }

    @Test
    func unknownToolReturnsError() async {
        let service = HackerNewsSummaryToolService(
            summarizeUseCase: SummarizeHackerNewsStoriesUseCase(repository: StubRepository())
        )

        let result = await service.callTool(name: "unknown_tool", arguments: nil)

        #expect(result.isError == true)
        #expect(extractText(result).contains("Unknown tool"))
    }
}

private struct StubRepository: HackerNewsSummaryRepository {
    func summarize(stories: [HackerNewsStoryForSummary], language _: String) async throws -> String {
        "Summary for \(stories.count) stories"
    }
}

private func extractText(_ result: CallTool.Result) -> String {
    result.content.compactMap {
        guard case .text(let text) = $0 else { return nil }
        return text
    }.joined(separator: "\n")
}

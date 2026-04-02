import Foundation
import MCP
import Testing
@testable import HackerNewsMCPServer

struct HackerNewsToolServiceTests {
    @Test
    func randomStoryToolReturnsFormattedResponse() async {
        let service = HackerNewsToolService(
            randomStoryUseCase: StubRandomStoryUseCase()
        )

        let result = await service.callTool(
            name: HackerNewsToolCatalog.randomStoryToolName,
            arguments: [:]
        )

        #expect(result.isError == false)
        #expect(extractText(result).contains("Random Hacker News story:"))
        #expect(extractText(result).contains("Title: Example title"))
        #expect(extractText(result).contains("ID: 123"))
    }

    @Test
    func randomStoryToolRejectsArguments() async {
        let service = HackerNewsToolService(
            randomStoryUseCase: StubRandomStoryUseCase()
        )

        let result = await service.callTool(
            name: HackerNewsToolCatalog.randomStoryToolName,
            arguments: ["unexpected": "value"]
        )

        #expect(result.isError == true)
        #expect(extractText(result).contains("does not accept arguments"))
    }

    @Test
    func unknownToolReturnsError() async {
        let service = HackerNewsToolService(
            randomStoryUseCase: StubRandomStoryUseCase()
        )

        let result = await service.callTool(name: "unknown_tool", arguments: nil)

        #expect(result.isError == true)
        #expect(extractText(result).contains("Unknown tool"))
    }
}

private struct StubRandomStoryUseCase: GetRandomStoryUseCaseProtocol {
    func execute() async throws -> HackerNewsStory {
        HackerNewsStory(
            id: 123,
            title: "Example title",
            author: "pg",
            url: URL(string: "https://example.com/story"),
            score: 42,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}

private func extractText(_ result: CallTool.Result) -> String {
    result.content.compactMap {
        guard case .text(let text) = $0 else { return nil }
        return text
    }.joined(separator: "\n")
}

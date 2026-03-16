import MCP
import Testing
@testable import HackerNewsTranslateMCPServer

struct HackerNewsTranslateToolServiceTests {
    @Test
    func translateToolReturnsLLMResponse() async {
        let service = HackerNewsTranslateToolService(
            translateUseCase: TranslateHackerNewsStoryUseCase(repository: StubRepository())
        )

        let result = await service.callTool(
            name: HackerNewsTranslateToolCatalog.translateToolName,
            arguments: [
                "story": "Random Hacker News story:\n- Title: Ship Swift 6\n- ID: 101\n- Author: alice\n- URL: https://example.com/1"
            ]
        )

        #expect(result.isError == false)
        #expect(extractText(result).contains("Translated story"))
    }

    @Test
    func translateToolRejectsMissingStory() async {
        let service = HackerNewsTranslateToolService(
            translateUseCase: TranslateHackerNewsStoryUseCase(repository: StubRepository())
        )

        let result = await service.callTool(
            name: HackerNewsTranslateToolCatalog.translateToolName,
            arguments: [:]
        )

        #expect(result.isError == true)
        #expect(extractText(result).contains("Argument 'story'"))
    }

    @Test
    func translateToolRejectsInvalidStoryFormat() async {
        let service = HackerNewsTranslateToolService(
            translateUseCase: TranslateHackerNewsStoryUseCase(repository: StubRepository())
        )

        let result = await service.callTool(
            name: HackerNewsTranslateToolCatalog.translateToolName,
            arguments: ["story": "bad format"]
        )

        #expect(result.isError == true)
        #expect(extractText(result).contains("Story must include '- Title: ...'."))
    }

    @Test
    func unknownToolReturnsError() async {
        let service = HackerNewsTranslateToolService(
            translateUseCase: TranslateHackerNewsStoryUseCase(repository: StubRepository())
        )

        let result = await service.callTool(name: "unknown_tool", arguments: nil)

        #expect(result.isError == true)
        #expect(extractText(result).contains("Unknown tool"))
    }
}

private struct StubRepository: HackerNewsTranslateRepository {
    func translate(story _: HackerNewsStoryForTranslation, language _: String) async throws -> String {
        "Translated story"
    }
}

private func extractText(_ result: CallTool.Result) -> String {
    result.content.compactMap {
        guard case .text(let text) = $0 else { return nil }
        return text
    }.joined(separator: "\n")
}

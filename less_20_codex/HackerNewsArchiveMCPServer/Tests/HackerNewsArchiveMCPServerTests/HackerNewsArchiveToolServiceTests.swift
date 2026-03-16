import Foundation
import MCP
import Testing
@testable import HackerNewsArchiveMCPServer

struct HackerNewsArchiveToolServiceTests {
    @Test
    func saveJSONToolStoresPayload() async {
        let service = HackerNewsArchiveToolService(
            saveUseCase: StubSaveUseCase(),
            recentFilesUseCase: StubRecentFilesUseCase()
        )

        let result = await service.callTool(
            name: HackerNewsArchiveToolCatalog.saveJSONToolName,
            arguments: ["json": "{\"title\":\"Example\"}"]
        )

        #expect(result.isError == false)
        #expect(extractText(result).contains("Saved Hacker News JSON:"))
    }

    @Test
    func saveJSONToolValidatesRequiredArgument() async {
        let service = HackerNewsArchiveToolService(
            saveUseCase: StubSaveUseCase(),
            recentFilesUseCase: StubRecentFilesUseCase()
        )

        let result = await service.callTool(
            name: HackerNewsArchiveToolCatalog.saveJSONToolName,
            arguments: [:]
        )

        #expect(result.isError == true)
        #expect(extractText(result).contains("Argument 'json' is required."))
    }

    @Test
    func listToolReturnsLatestFiles() async {
        let service = HackerNewsArchiveToolService(
            saveUseCase: StubSaveUseCase(),
            recentFilesUseCase: StubRecentFilesUseCase()
        )

        let result = await service.callTool(
            name: HackerNewsArchiveToolCatalog.listLatestToolName,
            arguments: nil
        )

        #expect(result.isError == false)
        #expect(extractText(result).contains("Latest saved Hacker News JSON files:"))
        #expect(extractText(result).contains("hackernews_1.json"))
        #expect(extractText(result).contains("hackernews_2.json"))
    }

    @Test
    func listToolRejectsArguments() async {
        let service = HackerNewsArchiveToolService(
            saveUseCase: StubSaveUseCase(),
            recentFilesUseCase: StubRecentFilesUseCase()
        )

        let result = await service.callTool(
            name: HackerNewsArchiveToolCatalog.listLatestToolName,
            arguments: ["unexpected": true]
        )

        #expect(result.isError == true)
        #expect(extractText(result).contains("does not accept arguments"))
    }
}

private struct StubSaveUseCase: SaveHackerNewsJSONUseCaseProtocol {
    func execute(json: String) throws -> ArchivedHackerNewsFile {
        .init(
            fileName: "hackernews_saved.json",
            savedAt: Date(),
            json: json
        )
    }
}

private struct StubRecentFilesUseCase: GetRecentHackerNewsFilesUseCaseProtocol {
    func execute(limit: Int) throws -> [ArchivedHackerNewsFile] {
        [
            .init(fileName: "hackernews_1.json", savedAt: Date(), json: "{\"id\":1}"),
            .init(fileName: "hackernews_2.json", savedAt: Date(), json: "{\"id\":2}")
        ]
    }
}

private func extractText(_ result: CallTool.Result) -> String {
    result.content.compactMap {
        guard case .text(let text) = $0 else { return nil }
        return text
    }.joined(separator: "\n")
}

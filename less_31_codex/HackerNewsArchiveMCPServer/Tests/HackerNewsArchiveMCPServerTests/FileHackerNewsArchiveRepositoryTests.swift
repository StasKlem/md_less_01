import Foundation
import Testing
@testable import HackerNewsArchiveMCPServer

struct FileHackerNewsArchiveRepositoryTests {
    @Test
    func saveAndListRecentReturnsThreeLatestFiles() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let repository = FileHackerNewsArchiveRepository(storageDirectory: tempDirectory)

        _ = try repository.save(json: "{\"id\":1}")
        Thread.sleep(forTimeInterval: 0.01)
        _ = try repository.save(json: "{\"id\":2}")
        Thread.sleep(forTimeInterval: 0.01)
        _ = try repository.save(json: "{\"id\":3}")
        Thread.sleep(forTimeInterval: 0.01)
        _ = try repository.save(json: "{\"id\":4}")

        let recent = try repository.listRecent(limit: 3)

        #expect(recent.count == 3)
        #expect(recent[0].json == "{\"id\":4}")
        #expect(recent[1].json == "{\"id\":3}")
        #expect(recent[2].json == "{\"id\":2}")
    }

    @Test
    func saveRejectsInvalidJSON() {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let repository = FileHackerNewsArchiveRepository(storageDirectory: tempDirectory)

        #expect(throws: HackerNewsArchiveToolError.self) {
            _ = try repository.save(json: "not-json")
        }
    }
}

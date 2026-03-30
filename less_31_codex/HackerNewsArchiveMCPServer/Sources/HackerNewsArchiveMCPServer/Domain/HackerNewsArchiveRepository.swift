import Foundation

protocol HackerNewsArchiveRepository: Sendable {
    func save(json: String) throws -> ArchivedHackerNewsFile
    func listRecent(limit: Int) throws -> [ArchivedHackerNewsFile]
}

import Foundation

protocol SaveHackerNewsJSONUseCaseProtocol: Sendable {
    func execute(json: String) throws -> ArchivedHackerNewsFile
}

struct SaveHackerNewsJSONUseCase: SaveHackerNewsJSONUseCaseProtocol {
    private let repository: HackerNewsArchiveRepository

    init(repository: HackerNewsArchiveRepository) {
        self.repository = repository
    }

    func execute(json: String) throws -> ArchivedHackerNewsFile {
        try repository.save(json: json)
    }
}

protocol GetRecentHackerNewsFilesUseCaseProtocol: Sendable {
    func execute(limit: Int) throws -> [ArchivedHackerNewsFile]
}

struct GetRecentHackerNewsFilesUseCase: GetRecentHackerNewsFilesUseCaseProtocol {
    private let repository: HackerNewsArchiveRepository

    init(repository: HackerNewsArchiveRepository) {
        self.repository = repository
    }

    func execute(limit: Int) throws -> [ArchivedHackerNewsFile] {
        try repository.listRecent(limit: limit)
    }
}

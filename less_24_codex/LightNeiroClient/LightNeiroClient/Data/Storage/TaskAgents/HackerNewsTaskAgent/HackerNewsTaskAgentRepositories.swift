import Foundation

struct FileHackerNewsTaskAgentStateRepository: HackerNewsTaskAgentStateRepositoryProtocol {
    private let fileManager: FileManager
    private let rootDirectoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileManager: FileManager = .default,
        rootDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.rootDirectoryURL = rootDirectoryURL ?? Self.defaultRootDirectoryURL(fileManager: fileManager)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func fetchSnapshot(sessionID: UUID, branchID: UUID) async throws -> HackerNewsTaskAgentSnapshot? {
        let fileURL = snapshotFileURL(sessionID: sessionID, branchID: branchID)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let envelope = try decoder.decode(PersistedEnvelope<HackerNewsTaskAgentSnapshot>.self, from: data)
        _ = envelope.schemaVersion
        return envelope.payload
    }

    func saveSnapshot(_ snapshot: HackerNewsTaskAgentSnapshot) async throws {
        try ensureDirectoryExists()
        let envelope = PersistedEnvelope(
            schemaVersion: HackerNewsTaskAgentSnapshot.schemaVersionCurrent,
            payload: snapshot
        )
        let data = try encoder.encode(envelope)
        try data.write(to: snapshotFileURL(sessionID: snapshot.sessionID, branchID: snapshot.branchID), options: .atomic)
    }

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: rootDirectoryURL.path) {
            try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        }
    }

    private func snapshotFileURL(sessionID: UUID, branchID: UUID) -> URL {
        rootDirectoryURL.appendingPathComponent("\(sessionID.uuidString.lowercased())-\(branchID.uuidString.lowercased()).json")
    }

    private static func defaultRootDirectoryURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("LightNeiroClient", isDirectory: true)
            .appendingPathComponent("task_flow", isDirectory: true)
            .appendingPathComponent("hacker_news_task_agent_state", isDirectory: true)
    }
}

struct FileHackerNewsArticleArchiveRepository: HackerNewsArticleArchiveRepositoryProtocol {
    private let fileManager: FileManager
    private let rootDirectoryURL: URL
    private let encoder = JSONEncoder()

    init(
        fileManager: FileManager = .default,
        rootDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.rootDirectoryURL = rootDirectoryURL ?? Self.defaultRootDirectoryURL(fileManager: fileManager)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    @discardableResult
    func saveArticle(_ record: HackerNewsTaskAgentArticleRecord) async throws -> URL {
        let directory = rootDirectoryURL
            .appendingPathComponent(record.sessionID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(record.branchID.uuidString.lowercased(), isDirectory: true)
        try ensureDirectoryExists(directory)

        let timestamp = Int(record.fetchedAt.timeIntervalSince1970)
        let fileName = String(format: "request-%05d-%d.json", record.requestNumber, timestamp)
        let fileURL = directory.appendingPathComponent(fileName)
        let data = try encoder.encode(record)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private func ensureDirectoryExists(_ url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private static func defaultRootDirectoryURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("LightNeiroClient", isDirectory: true)
            .appendingPathComponent("task_flow", isDirectory: true)
            .appendingPathComponent("hacker_news_articles", isDirectory: true)
    }
}

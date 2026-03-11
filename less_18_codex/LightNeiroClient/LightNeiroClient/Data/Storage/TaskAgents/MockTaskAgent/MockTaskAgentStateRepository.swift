import Foundation

struct FileMockTaskAgentStateRepository: MockTaskAgentStateRepositoryProtocol {
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

    func fetchSnapshot(sessionID: UUID, branchID: UUID) async throws -> MockTaskAgentSnapshot? {
        let fileURL = snapshotFileURL(sessionID: sessionID, branchID: branchID)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let envelope = try decoder.decode(PersistedEnvelope<MockTaskAgentSnapshot>.self, from: data)
        _ = envelope.schemaVersion
        return envelope.payload
    }

    func saveSnapshot(_ snapshot: MockTaskAgentSnapshot) async throws {
        try ensureDirectoryExists()
        let envelope = PersistedEnvelope(
            schemaVersion: MockTaskAgentSnapshot.schemaVersionCurrent,
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
            .appendingPathComponent("mock_task_agent_state", isDirectory: true)
    }
}

struct FileCounterTaskAgentStateRepository: CounterTaskAgentStateRepositoryProtocol {
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

    func fetchSnapshot(sessionID: UUID, branchID: UUID) async throws -> CounterTaskAgentSnapshot? {
        let fileURL = snapshotFileURL(sessionID: sessionID, branchID: branchID)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let envelope = try decoder.decode(PersistedEnvelope<CounterTaskAgentSnapshot>.self, from: data)
        _ = envelope.schemaVersion
        return envelope.payload
    }

    func saveSnapshot(_ snapshot: CounterTaskAgentSnapshot) async throws {
        try ensureDirectoryExists()
        let envelope = PersistedEnvelope(
            schemaVersion: CounterTaskAgentSnapshot.schemaVersionCurrent,
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
            .appendingPathComponent("counter_task_agent_state", isDirectory: true)
    }
}

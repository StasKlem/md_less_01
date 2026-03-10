import Foundation

private struct PersistedEnvelope<T: Codable>: Codable {
    let schemaVersion: Int
    let payload: T
}

struct FileVacationPlanningStateRepository: VacationPlanningStateRepositoryProtocol {
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

    func fetchSnapshot(sessionID: UUID, branchID: UUID) async throws -> VacationPlanningSnapshot? {
        let fileURL = snapshotFileURL(sessionID: sessionID, branchID: branchID)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let envelope = try decoder.decode(PersistedEnvelope<VacationPlanningSnapshot>.self, from: data)
        // Backward compatibility: allow older or newer version and trust payload checks in domain layer.
        _ = envelope.schemaVersion
        return envelope.payload
    }

    func saveSnapshot(_ snapshot: VacationPlanningSnapshot) async throws {
        try ensureDirectoryExists()
        let envelope = PersistedEnvelope(
            schemaVersion: VacationPlanningSnapshot.schemaVersionCurrent,
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
            .appendingPathComponent("state", isDirectory: true)
    }
}

struct FileVacationPlanRepository: VacationPlanRepositoryProtocol {
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

    func fetchFinalPlan(sessionID: UUID, branchID: UUID) async throws -> VacationPlan? {
        let fileURL = planFileURL(sessionID: sessionID, branchID: branchID)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let envelope = try decoder.decode(PersistedEnvelope<VacationPlan>.self, from: data)
        _ = envelope.schemaVersion
        return envelope.payload
    }

    func saveFinalPlan(_ plan: VacationPlan) async throws {
        try ensureDirectoryExists()
        let envelope = PersistedEnvelope(
            schemaVersion: VacationPlanningSnapshot.schemaVersionCurrent,
            payload: plan
        )
        let data = try encoder.encode(envelope)
        try data.write(to: planFileURL(sessionID: plan.sessionID, branchID: plan.branchID), options: .atomic)
    }

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: rootDirectoryURL.path) {
            try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        }
    }

    private func planFileURL(sessionID: UUID, branchID: UUID) -> URL {
        rootDirectoryURL.appendingPathComponent("\(sessionID.uuidString.lowercased())-\(branchID.uuidString.lowercased()).json")
    }

    private static func defaultRootDirectoryURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("LightNeiroClient", isDirectory: true)
            .appendingPathComponent("task_flow", isDirectory: true)
            .appendingPathComponent("plans", isDirectory: true)
    }
}

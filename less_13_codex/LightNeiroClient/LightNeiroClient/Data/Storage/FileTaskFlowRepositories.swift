import Foundation

actor FileTaskProgressRepository: TaskProgressRepositoryProtocol {
    private let fileManager: FileManager
    private let rootDirectoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default, rootDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        if let rootDirectoryURL {
            self.rootDirectoryURL = rootDirectoryURL
        } else {
            self.rootDirectoryURL = Self.defaultRootDirectoryURL(fileManager: fileManager)
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func fetch(branchID: UUID) async throws -> TaskProgressState? {
        let fileURL = fileURL(for: branchID)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(TaskProgressState.self, from: data)
    }

    func save(branchID: UUID, state: TaskProgressState) async throws {
        try ensureDirectoryExists()
        let data = try encoder.encode(state)
        try data.write(to: fileURL(for: branchID), options: .atomic)
    }

    func reset(branchID: UUID) async throws {
        let fileURL = fileURL(for: branchID)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: rootDirectoryURL.path) {
            try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        }
    }

    private func fileURL(for branchID: UUID) -> URL {
        rootDirectoryURL.appendingPathComponent("\(branchID.uuidString).json", isDirectory: false)
    }

    private static func defaultRootDirectoryURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("LightNeiroClient", isDirectory: true)
            .appendingPathComponent("task_progress", isDirectory: true)
    }
}

actor FileStageArtifactRepository: StageArtifactRepositoryProtocol {
    private let fileManager: FileManager
    private let rootDirectoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default, rootDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        if let rootDirectoryURL {
            self.rootDirectoryURL = rootDirectoryURL
        } else {
            self.rootDirectoryURL = Self.defaultRootDirectoryURL(fileManager: fileManager)
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func fetchArtifacts(branchID: UUID) async throws -> [StageArtifact] {
        try load(branchID: branchID).sorted { $0.createdAt < $1.createdAt }
    }

    func fetchLatest(branchID: UUID, stage: AgentStage) async throws -> StageArtifact? {
        try load(branchID: branchID)
            .filter { $0.stage == stage }
            .sorted { $0.createdAt < $1.createdAt }
            .last
    }

    func save(_ artifact: StageArtifact) async throws {
        var current = try load(branchID: artifact.branchID)
        current.removeAll { $0.id == artifact.id }
        current.append(artifact)
        try persist(artifacts: current, branchID: artifact.branchID)
    }

    func reset(branchID: UUID) async throws {
        let fileURL = fileURL(for: branchID)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    private func load(branchID: UUID) throws -> [StageArtifact] {
        let fileURL = fileURL(for: branchID)
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([StageArtifact].self, from: data)
    }

    private func persist(artifacts: [StageArtifact], branchID: UUID) throws {
        try ensureDirectoryExists()
        let data = try encoder.encode(artifacts)
        try data.write(to: fileURL(for: branchID), options: .atomic)
    }

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: rootDirectoryURL.path) {
            try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        }
    }

    private func fileURL(for branchID: UUID) -> URL {
        rootDirectoryURL.appendingPathComponent("\(branchID.uuidString).json", isDirectory: false)
    }

    private static func defaultRootDirectoryURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("LightNeiroClient", isDirectory: true)
            .appendingPathComponent("stage_artifacts", isDirectory: true)
    }
}

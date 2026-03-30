import Foundation

private enum DialogStorageSchema {
    static let current = 1
}

struct FileMessageRepository: MessageRepositoryProtocol {
    private let fileManager: FileManager
    private let rootDirectoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default, rootDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        self.rootDirectoryURL = rootDirectoryURL ?? Self.defaultRootDirectoryURL(fileManager: fileManager)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func fetchMessages() async throws -> [ChatMessage] {
        try migrateLegacyIfNeeded()
        guard fileManager.fileExists(atPath: messagesFileURL.path) else { return [] }
        let data = try Data(contentsOf: messagesFileURL)
        let envelope = try decoder.decode(PersistedEnvelope<[ChatMessage]>.self, from: data)
        _ = envelope.schemaVersion
        return envelope.payload.sorted { $0.createdAt < $1.createdAt }
    }

    func saveMessage(_ message: ChatMessage) async throws {
        var current = try await fetchMessages()
        current.append(message)
        try persist(messages: current)
    }

    func clearAll() async throws {
        guard fileManager.fileExists(atPath: messagesFileURL.path) else { return }
        try fileManager.removeItem(at: messagesFileURL)
    }

    private func persist(messages: [ChatMessage]) throws {
        try ensureDirectoryExists()
        let envelope = PersistedEnvelope(schemaVersion: DialogStorageSchema.current, payload: messages)
        let data = try encoder.encode(envelope)
        try data.write(to: messagesFileURL, options: .atomic)
    }

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: rootDirectoryURL.path) {
            try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        }
    }

    private func migrateLegacyIfNeeded() throws {
        guard !fileManager.fileExists(atPath: messagesFileURL.path) else { return }

        let candidates = [
            rootDirectoryURL.appendingPathComponent("messages_by_branch.json"),
            rootDirectoryURL.appendingPathComponent("legacy_messages.json")
        ]

        for legacyURL in candidates where fileManager.fileExists(atPath: legacyURL.path) {
            let data = try Data(contentsOf: legacyURL)
            if let legacyMap = try? decoder.decode([String: [ChatMessage]].self, from: data) {
                let merged = legacyMap.values.flatMap { $0 }.sorted { $0.createdAt < $1.createdAt }
                try persist(messages: merged)
                return
            }
            if let legacy = try? decoder.decode([ChatMessage].self, from: data) {
                try persist(messages: legacy.sorted { $0.createdAt < $1.createdAt })
                return
            }
        }
    }

    private var messagesFileURL: URL {
        rootDirectoryURL.appendingPathComponent("messages.json", isDirectory: false)
    }

    private static func defaultRootDirectoryURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("LightNeiroClient", isDirectory: true)
            .appendingPathComponent("dialog", isDirectory: true)
    }
}

actor FileShortTermMemoryRepository: ShortTermMemoryRepositoryProtocol {
    private let fileManager: FileManager
    private let rootDirectoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default, rootDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        self.rootDirectoryURL = rootDirectoryURL ?? Self.defaultRootDirectoryURL(fileManager: fileManager)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func fetchSnapshot() async throws -> ShortTermMemorySnapshot? {
        guard fileManager.fileExists(atPath: snapshotFileURL.path) else { return nil }
        let data = try Data(contentsOf: snapshotFileURL)
        let envelope = try decoder.decode(PersistedEnvelope<ShortTermMemorySnapshot>.self, from: data)
        _ = envelope.schemaVersion
        return envelope.payload
    }

    func saveSnapshot(_ snapshot: ShortTermMemorySnapshot) async throws {
        try ensureDirectoryExists()
        let envelope = PersistedEnvelope(schemaVersion: DialogStorageSchema.current, payload: snapshot)
        let data = try encoder.encode(envelope)
        try data.write(to: snapshotFileURL, options: .atomic)
    }

    func clear() async throws {
        guard fileManager.fileExists(atPath: snapshotFileURL.path) else { return }
        try fileManager.removeItem(at: snapshotFileURL)
    }

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: rootDirectoryURL.path) {
            try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        }
    }

    private var snapshotFileURL: URL {
        rootDirectoryURL.appendingPathComponent("short_term.json", isDirectory: false)
    }

    private static func defaultRootDirectoryURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("LightNeiroClient", isDirectory: true)
            .appendingPathComponent("dialog", isDirectory: true)
    }
}

actor FileWorkingMemoryRepository: WorkingMemoryRepositoryProtocol {
    private let fileManager: FileManager
    private let rootDirectoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default, rootDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        self.rootDirectoryURL = rootDirectoryURL ?? Self.defaultRootDirectoryURL(fileManager: fileManager)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func fetchActive() async throws -> [WorkingMemoryItem] {
        let items = try loadAll()
        return items.filter { $0.status == .active }
    }

    func upsert(items: [WorkingMemoryItem]) async throws {
        var current = try loadAll()
        for item in items {
            current.removeAll { $0.key == item.key }
            current.append(item)
        }
        try persist(items: current)
    }

    func resolve(keys: [String]) async throws {
        guard !keys.isEmpty else { return }
        let keySet = Set(keys)
        let now = Date()
        let current = try loadAll()
        let resolved = current.map { item in
            guard keySet.contains(item.key) else { return item }
            return WorkingMemoryItem(
                id: item.id,
                taskID: item.taskID,
                key: item.key,
                value: item.value,
                status: .resolved,
                confidence: item.confidence,
                updatedAt: now
            )
        }
        try persist(items: resolved)
    }

    func clearAll() async throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    private func loadAll() throws -> [WorkingMemoryItem] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let envelope = try decoder.decode(PersistedEnvelope<[WorkingMemoryItem]>.self, from: data)
        _ = envelope.schemaVersion
        return envelope.payload
    }

    private func persist(items: [WorkingMemoryItem]) throws {
        try ensureDirectoryExists()
        let envelope = PersistedEnvelope(schemaVersion: DialogStorageSchema.current, payload: items)
        let data = try encoder.encode(envelope)
        try data.write(to: fileURL, options: .atomic)
    }

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: rootDirectoryURL.path) {
            try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        }
    }

    private var fileURL: URL {
        rootDirectoryURL.appendingPathComponent("working_memory.json", isDirectory: false)
    }

    private static func defaultRootDirectoryURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("LightNeiroClient", isDirectory: true)
            .appendingPathComponent("dialog", isDirectory: true)
    }
}

actor FileFactsRepository: FactsRepositoryProtocol {
    private var facts: [StickyFact] = []

    func fetchFacts() async throws -> [StickyFact] {
        facts
    }

    func upsertFacts(facts: [StickyFact]) async throws {
        self.facts = facts
    }
}

actor FileMetricsRepository: MetricsRepositoryProtocol {
    private let fileManager: FileManager
    private let rootDirectoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default, rootDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        self.rootDirectoryURL = rootDirectoryURL ?? Self.defaultRootDirectoryURL(fileManager: fileManager)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func appendMetric(_ metric: RequestMetric) async throws {
        var current = try loadAll()
        current.append(metric)
        try persist(metrics: current)
    }

    func fetchMetrics() async throws -> [RequestMetric] {
        try loadAll()
    }

    func clearAll() async throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    private func loadAll() throws -> [RequestMetric] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let envelope = try decoder.decode(PersistedEnvelope<[RequestMetric]>.self, from: data)
        _ = envelope.schemaVersion
        return envelope.payload
    }

    private func persist(metrics: [RequestMetric]) throws {
        try ensureDirectoryExists()
        let envelope = PersistedEnvelope(schemaVersion: DialogStorageSchema.current, payload: metrics)
        let data = try encoder.encode(envelope)
        try data.write(to: fileURL, options: .atomic)
    }

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: rootDirectoryURL.path) {
            try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        }
    }

    private var fileURL: URL {
        rootDirectoryURL.appendingPathComponent("metrics.json", isDirectory: false)
    }

    private static func defaultRootDirectoryURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("LightNeiroClient", isDirectory: true)
            .appendingPathComponent("dialog", isDirectory: true)
    }
}

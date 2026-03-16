import Foundation

actor FileLongTermMemoryRepository: LongTermMemoryRepositoryProtocol {
    private let fileManager: FileManager
    private let rootDirectoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileManager: FileManager = .default,
        rootDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        if let rootDirectoryURL {
            self.rootDirectoryURL = rootDirectoryURL
        } else {
            self.rootDirectoryURL = Self.defaultRootDirectoryURL(fileManager: fileManager)
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func fetch(sessionID: UUID, namespaces: [LongTermMemoryNamespace]?) async throws -> [LongTermMemoryItem] {
        let items = try load(sessionID: sessionID)
        guard let namespaces, !namespaces.isEmpty else { return items }
        let namespaceSet = Set(namespaces)
        return items.filter { namespaceSet.contains($0.namespace) }
    }

    func upsert(sessionID: UUID, items: [LongTermMemoryItem]) async throws {
        var current = try load(sessionID: sessionID)
        for item in items where item.sessionID == sessionID {
            current.removeAll { $0.namespace == item.namespace && $0.key == item.key }
            current.append(item)
        }
        try persist(items: current, sessionID: sessionID)
    }

    func delete(sessionID: UUID, keys: [String]) async throws {
        guard !keys.isEmpty else { return }
        var current = try load(sessionID: sessionID)
        let keySet = Set(keys)
        current.removeAll { keySet.contains($0.key) }
        try persist(items: current, sessionID: sessionID)
    }

    private func load(sessionID: UUID) throws -> [LongTermMemoryItem] {
        let fileURL = fileURL(for: sessionID)
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([LongTermMemoryItem].self, from: data)
    }

    private func persist(items: [LongTermMemoryItem], sessionID: UUID) throws {
        try ensureDirectoryExists()
        let fileURL = fileURL(for: sessionID)
        let data = try encoder.encode(items)
        try data.write(to: fileURL, options: .atomic)
    }

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: rootDirectoryURL.path) {
            try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        }
    }

    private func fileURL(for sessionID: UUID) -> URL {
        rootDirectoryURL.appendingPathComponent("\(sessionID.uuidString).json", isDirectory: false)
    }

    private static func defaultRootDirectoryURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("LightNeiroClient", isDirectory: true)
            .appendingPathComponent("long_term_memory", isDirectory: true)
    }
}

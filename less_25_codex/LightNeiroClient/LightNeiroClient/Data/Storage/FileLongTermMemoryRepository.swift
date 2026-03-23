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

    func fetch(namespaces: [LongTermMemoryNamespace]?) async throws -> [LongTermMemoryItem] {
        let items = try load()
        guard let namespaces, !namespaces.isEmpty else { return items }
        let namespaceSet = Set(namespaces)
        return items.filter { namespaceSet.contains($0.namespace) }
    }

    func upsert(items: [LongTermMemoryItem]) async throws {
        var current = try load()
        for item in items {
            current.removeAll { $0.namespace == item.namespace && $0.key == item.key }
            current.append(item)
        }
        try persist(items: current)
    }

    func delete(keys: [String]) async throws {
        guard !keys.isEmpty else { return }
        var current = try load()
        let keySet = Set(keys)
        current.removeAll { keySet.contains($0.key) }
        try persist(items: current)
    }

    func clearAll() async throws {
        let url = fileURL()
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func load() throws -> [LongTermMemoryItem] {
        let fileURL = fileURL()
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([LongTermMemoryItem].self, from: data)
    }

    private func persist(items: [LongTermMemoryItem]) throws {
        try ensureDirectoryExists()
        let fileURL = fileURL()
        let data = try encoder.encode(items)
        try data.write(to: fileURL, options: .atomic)
    }

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: rootDirectoryURL.path) {
            try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        }
    }

    private func fileURL() -> URL {
        rootDirectoryURL.appendingPathComponent("global.json", isDirectory: false)
    }

    private static func defaultRootDirectoryURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("LightNeiroClient", isDirectory: true)
            .appendingPathComponent("long_term_memory", isDirectory: true)
    }
}

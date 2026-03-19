import Foundation

struct FileHackerNewsArchiveRepository: HackerNewsArchiveRepository {
    private let storageDirectory: URL

    init(storageDirectory: URL) {
        self.storageDirectory = storageDirectory
    }

    func save(json: String) throws -> ArchivedHackerNewsFile {
        try JSONValidator.validate(json: json)
        try ensureStorageDirectoryExists()

        let timestamp = Date()
        let fileName = FileNameGenerator.makeFileName(for: timestamp)
        let fileURL = storageDirectory.appendingPathComponent(fileName)

        do {
            try Data(json.utf8).write(to: fileURL, options: .atomic)
        } catch {
            throw HackerNewsArchiveToolError.fileIO("Could not write file '\(fileName)': \(error.localizedDescription)")
        }

        return ArchivedHackerNewsFile(fileName: fileName, savedAt: timestamp, json: json)
    }

    func listRecent(limit: Int) throws -> [ArchivedHackerNewsFile] {
        guard limit > 0 else {
            return []
        }

        try ensureStorageDirectoryExists()
        let fileManager = FileManager.default

        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: storageDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw HackerNewsArchiveToolError.fileIO("Could not read storage directory: \(error.localizedDescription)")
        }

        let entries = try urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .map { url in
                let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
                let modifiedAt = values.contentModificationDate ?? .distantPast
                let data = try Data(contentsOf: url)
                guard let json = String(data: data, encoding: .utf8) else {
                    throw HackerNewsArchiveToolError.fileIO("File '\(url.lastPathComponent)' is not valid UTF-8.")
                }
                return ArchivedHackerNewsFile(fileName: url.lastPathComponent, savedAt: modifiedAt, json: json)
            }
            .sorted(by: { $0.savedAt > $1.savedAt })

        return Array(entries.prefix(limit))
    }

    private func ensureStorageDirectoryExists() throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: storageDirectory.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw HackerNewsArchiveToolError.fileIO(
                    "Configured storage path is not a directory: \(storageDirectory.path)"
                )
            }
            return
        }

        do {
            try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        } catch {
            throw HackerNewsArchiveToolError.fileIO(
                "Could not create storage directory: \(error.localizedDescription)"
            )
        }
    }
}

private enum JSONValidator {
    static func validate(json: String) throws {
        guard let data = json.data(using: .utf8) else {
            throw HackerNewsArchiveToolError.invalidArguments("Argument 'json' must be a UTF-8 string.")
        }

        do {
            _ = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw HackerNewsArchiveToolError.invalidArguments("Argument 'json' must contain valid JSON.")
        }
    }
}

private enum FileNameGenerator {
    static func makeFileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
        return "hackernews_\(formatter.string(from: date)).json"
    }
}

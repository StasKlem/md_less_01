import Foundation

enum LogLevel: String, Sendable {
    case debug
    case info
    case warn
    case error

    var severity: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warn: return 2
        case .error: return 3
        }
    }

    static func parse(_ raw: String?) throws -> LogLevel {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return .info
        }

        guard let value = LogLevel(rawValue: raw.lowercased()) else {
            throw HackerNewsArchiveToolError.invalidArguments(
                "HACKERNEWS_ARCHIVE_LOG_LEVEL must be one of: debug, info, warn, error."
            )
        }

        return value
    }
}

protocol Logger: Sendable {
    func log(_ level: LogLevel, _ message: String)
}

struct StderrLogger: Logger {
    private let component: String
    private let minLevel: LogLevel

    init(component: String, minLevel: LogLevel) {
        self.component = component
        self.minLevel = minLevel
    }

    func log(_ level: LogLevel, _ message: String) {
        guard level.severity >= minLevel.severity else {
            return
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [\(level.rawValue.uppercased())] [\(component)] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}

extension Logger {
    func debug(_ message: String) { log(.debug, message) }
    func info(_ message: String) { log(.info, message) }
    func warn(_ message: String) { log(.warn, message) }
    func error(_ message: String) { log(.error, message) }
}

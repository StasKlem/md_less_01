import Foundation

enum LogLevel: Int, Comparable, Sendable {
    case debug = 0
    case info = 1
    case warn = 2
    case error = 3

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func parse(_ value: String?) -> LogLevel {
        guard let value = value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return .info
        }

        switch value.lowercased() {
        case "debug":
            return .debug
        case "info":
            return .info
        case "warn", "warning":
            return .warn
        case "error":
            return .error
        default:
            return .info
        }
    }
}

struct StderrLogger: Sendable {
    private let component: String
    private let minLevel: LogLevel

    init(component: String, minLevel: LogLevel) {
        self.component = component
        self.minLevel = minLevel
    }

    func debug(_ message: String) {
        log(level: .debug, message: message)
    }

    func info(_ message: String) {
        log(level: .info, message: message)
    }

    func warn(_ message: String) {
        log(level: .warn, message: message)
    }

    func error(_ message: String) {
        log(level: .error, message: message)
    }

    private func log(level: LogLevel, message: String) {
        guard level >= minLevel else {
            return
        }

        let line = "[\(component)] [\(levelLabel(for: level))] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    private func levelLabel(for level: LogLevel) -> String {
        switch level {
        case .debug:
            return "DEBUG"
        case .info:
            return "INFO"
        case .warn:
            return "WARN"
        case .error:
            return "ERROR"
        }
    }
}

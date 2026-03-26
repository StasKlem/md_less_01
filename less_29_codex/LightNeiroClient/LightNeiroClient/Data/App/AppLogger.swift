import Foundation

/// Единый логгер приложения с форматированием времени до миллисекунд.
final class AppLogger: @unchecked Sendable {
    /// Общий singleton-экземпляр логгера.
    static let shared = AppLogger()

    private let lock = NSLock()
    private let formatter: DateFormatter

    private init() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        self.formatter = formatter
    }

    nonisolated func debug(_ message: String, category: String = "general") {
        log(level: .debug, message: message, category: category)
    }

    nonisolated func info(_ message: String, category: String = "general") {
        log(level: .info, message: message, category: category)
    }

    nonisolated func warning(_ message: String, category: String = "general") {
        log(level: .warning, message: message, category: category)
    }

    nonisolated func error(_ message: String, category: String = "general") {
        log(level: .error, message: message, category: category)
    }

    nonisolated private func log(level: LogLevel, message: String, category: String) {
        let line = makeLogLine(level: level, category: category, message: message, date: Date())
        print(line)
    }

    nonisolated func makeLogLine(level: LogLevel, category: String, message: String, date: Date) -> String {
        let timestamp = timestampString(from: date)
        return "[\(timestamp)] [\(level.rawValue)] [\(category)] \(message)"
    }

    nonisolated func timestampString(from date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return formatter.string(from: date)
    }

}

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
}

func log(_ message: String, category: String = "general") {
    AppLogger.shared.info(message, category: category)
}

func log(_ object: Any, category: String = "general") {
    AppLogger.shared.info(stringify(object), category: category)
}

func stringify(_ object: Any) -> String {
    String(describing: object)
}

func prettyJSONString(from value: Any) -> String {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]),
          let string = String(data: data, encoding: .utf8) else {
        return String(describing: value)
    }
    return string
}

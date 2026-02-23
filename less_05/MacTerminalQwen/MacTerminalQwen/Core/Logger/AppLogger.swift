//
//  AppLogger.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation
import os.log

/// Уровни логирования
enum LogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Единый механизм логирования для всего приложения.
/// Использует os.log для производительности и интеграции с Console.app.
final actor AppLogger {
    
    // MARK: - Singleton
    
    static let shared = AppLogger()
    
    // MARK: - Properties
    
    private let logger: OSLog
    private var currentLevel: LogLevel = .debug
    
    // MARK: - Initialization
    
    init(subsystem: String = Bundle.main.bundleIdentifier ?? "MacTerminalQwen", category: String = "App") {
        self.logger = OSLog(subsystem: subsystem, category: category)
    }
    
    // MARK: - Configuration
    
    /// Установить минимальный уровень логирования
    func setLevel(_ level: LogLevel) {
        currentLevel = level
    }
    
    // MARK: - Logging Methods
    
    /// Логирование отладочных сообщений
    func debug(_ message: @autoclosure () -> String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .debug, message(), file: file, function: function, line: line)
    }
    
    /// Логирование информационных сообщений
    func info(_ message: @autoclosure () -> String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .info, message(), file: file, function: function, line: line)
    }
    
    /// Логирование предупреждений
    func warning(_ message: @autoclosure () -> String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .warning, message(), file: file, function: function, line: line)
    }
    
    /// Логирование ошибок
    func error(_ message: @autoclosure () -> String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .error, message(), file: file, function: function, line: line)
    }
    
    /// Логирование ошибки с деталями
    func error(_ error: Error, file: String = #file, function: String = #function, line: Int = #line) {
        let message = "[\(type(of: error))] \(error.localizedDescription)"
        log(level: .error, message, file: file, function: function, line: line)
    }
    
    // MARK: - Private
    
    private func log(level: LogLevel, _ message: @autoclosure () -> String, file: String, function: String, line: Int) {
        guard level >= currentLevel else { return }
        
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let formattedMessage = "[\(fileName):\(line)] \(function) — \(message())"
        
        let logType: OSLogType
        switch level {
        case .debug:
            logType = .debug
        case .info:
            logType = .info
        case .warning:
            logType = .default
        case .error:
            logType = .error
        }
        
        os_log("%{public}@", log: logger, type: logType, formattedMessage)
    }
}

// MARK: - Global Convenience Functions

/// Глобальные функции для удобного логирования
func logDebug(_ message: @autoclosure @escaping () -> String, file: String = #file, function: String = #function, line: Int = #line) {
    Task.detached {
        await AppLogger.shared.debug(message(), file: file, function: function, line: line)
    }
}

func logInfo(_ message: @autoclosure @escaping () -> String, file: String = #file, function: String = #function, line: Int = #line) {
    Task.detached {
        await AppLogger.shared.info(message(), file: file, function: function, line: line)
    }
}

func logWarning(_ message: @autoclosure @escaping () -> String, file: String = #file, function: String = #function, line: Int = #line) {
    Task.detached {
        await AppLogger.shared.warning(message(), file: file, function: function, line: line)
    }
}

func logError(_ message: @autoclosure @escaping () -> String, file: String = #file, function: String = #function, line: Int = #line) {
    Task.detached {
        await AppLogger.shared.error(message(), file: file, function: function, line: line)
    }
}

func logError(_ error: Error, file: String = #file, function: String = #function, line: Int = #line) {
    Task.detached {
        await AppLogger.shared.error(error, file: file, function: function, line: line)
    }
}

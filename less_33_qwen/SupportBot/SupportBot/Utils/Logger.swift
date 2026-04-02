//
//  Logger.swift
//  SupportBot
//
//  Created by Stas Klem on 02.04.2026.
//

import Foundation
import Logging

/// Настройка логирования для SupportBot
@MainActor
final class LoggerSetup {
    private static var isConfigured = false
    
    /// Инициализация логгера
    static func setup(config: LoggingConfig? = nil) -> Logger {
        guard !isConfigured else {
            return Logger(label: "com.supportbot")
        }
        
        // Определяем уровень логирования
        var logLevel = Logger.Level.info
        if let levelString = config?.level {
            switch levelString.lowercased() {
            case "debug": logLevel = .debug
            case "info": logLevel = .info
            case "warn", "warning": logLevel = .warning
            case "error": logLevel = .error
            default: logLevel = .info
            }
        }
        
        // Устанавливаем handler для вывода в консоль
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = logLevel
            return handler
        }
        
        isConfigured = true
        return Logger(label: "com.supportbot")
    }
}

extension Logger {
    /// Создать логгер с меткой SupportBot
    static func supportBot(category: String = "main") -> Logger {
        Logger(label: "com.supportbot.\(category)")
    }
}

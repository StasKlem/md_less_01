//
//  AppError.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

/// Базовый тип ошибок приложения.
/// Используется для единого механизма обработки ошибок во всех слоях.
enum AppError: LocalizedError {
    
    /// Ошибка валидации данных
    case validation(String)
    
    /// Ошибка сети (обёртка над NetworkError)
    case network(NetworkError)
    
    /// Ошибка хранения данных
    case storage(String)
    
    /// Ошибка доступа к Keychain
    case keychain(String)
    
    /// Ошибка парсинга данных
    case parsing(String)
    
    /// Неизвестная ошибка
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .validation(let message):
            return message
        case .network(let error):
            return error.errorDescription
        case .storage(let message):
            return "Ошибка хранения: \(message)"
        case .keychain(let message):
            return "Ошибка безопасности: \(message)"
        case .parsing(let message):
            return "Ошибка обработки данных: \(message)"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .validation:
            return "Проверьте корректность введённых данных"
        case .network(let error):
            return error.recoverySuggestion
        case .storage:
            return "Попробуйте перезапустить приложение"
        case .keychain:
            return "Проверьте настройки безопасности системы"
        case .parsing:
            return "Попробуйте повторить запрос"
        case .unknown:
            return "Попробуйте повторить операцию"
        }
    }
}

// MARK: - Convenience Initializers

extension AppError {
    static func invalidURL(_ url: String) -> AppError {
        .validation("Некорректный URL: \(url)")
    }
    
    static func emptyMessage(_ field: String = "Сообщение") -> AppError {
        .validation("\(field) не может быть пустым")
    }
    
    static func invalidSettings(_ field: String) -> AppError {
        .validation("Поле '\(field)' заполнено некорректно")
    }
}

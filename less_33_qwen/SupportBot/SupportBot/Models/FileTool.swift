//
//  FileTool.swift
//  SupportBot
//
//  Created by Stas Klem on 03.04.2026.
//

import Foundation

/// Доступные инструменты для работы с файлами
enum FileTool: String, CaseIterable, Codable {
    case read
    case search
    case create
    case edit
    case diff
    case analyze
    case list
    case invariants

    /// Название инструмента для отображения
    var displayName: String {
        switch self {
        case .read: return "📖 Чтение файла"
        case .search: return "🔍 Поиск в файлах"
        case .create: return "📝 Создание файла"
        case .edit: return "✏️  Изменение файла"
        case .diff: return "📊 Diff файла"
        case .analyze: return "🔬 Анализ проекта"
        case .list: return "📁 Список файлов"
        case .invariants: return "✅ Проверка инвариантов"
        }
    }

    /// Описание использования
    var usage: String {
        switch self {
        case .read:
            return "/files <path> — прочитать файл или директорию"
        case .search:
            return "/search <pattern> [path] — поиск по содержимому файлов"
        case .create:
            return "/create <path> — создать новый файл"
        case .edit:
            return "/edit <path> — изменить файл (укажите что заменить)"
        case .diff:
            return "/diff <path> — показать изменения файла"
        case .analyze:
            return "/analyze — анализ структуры проекта"
        case .list:
            return "/list [path] — список файлов в директории"
        case .invariants:
            return "/invariants — проверка соответствия правилам"
        }
    }

    /// Пример использования
    var example: String {
        switch self {
        case .read:
            return "/files SupportBot/App.swift"
        case .search:
            return "/search LLMProvider SupportBot/"
        case .create:
            return "/create CHANGELOG.md"
        case .edit:
            return "/edit README.md"
        case .diff:
            return "/diff SupportBot/App.swift"
        case .analyze:
            return "/analyze"
        case .list:
            return "/list SupportBot/"
        case .invariants:
            return "/invariants"
        }
    }
}

/// Результат выполнения инструмента
struct ToolResult {
    let tool: FileTool
    let success: Bool
    let output: String
    let metadata: [String: String]?

    init(tool: FileTool, success: Bool, output: String, metadata: [String: String]? = nil) {
        self.tool = tool
        self.success = success
        self.output = output
        self.metadata = metadata
    }

    /// Форматированный вывод результата
    func formatted() -> String {
        var result = ""
        result += "\(tool.displayName)\n"
        result += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        if success {
            result += "✅ Успешно\n\n"
        } else {
            result += "❌ Ошибка\n\n"
        }
        result += output
        if let metadata = metadata, !metadata.isEmpty {
            result += "\n\n📊 Метаданные:\n"
            for (key, value) in metadata {
                result += "  • \(key): \(value)\n"
            }
        }
        return result
    }
}

/// Ошибка инструмента
enum ToolError: LocalizedError {
    case invalidArguments(String)
    case fileNotFound(String)
    case permissionDenied(String)
    case invalidPath(String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return "Неверные аргументы: \(message)"
        case .fileNotFound(let path):
            return "Файл не найден: \(path)"
        case .permissionDenied(let message):
            return "Доступ запрещён: \(message)"
        case .invalidPath(let path):
            return "Неверный путь: \(path)"
        case .operationFailed(let message):
            return "Ошибка операции: \(message)"
        }
    }
}

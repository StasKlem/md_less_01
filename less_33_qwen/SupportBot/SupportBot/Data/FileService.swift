//
//  FileService.swift
//  SupportBot
//
//  Created by Stas Klem on 03.04.2026.
//

import Foundation
import Logging

/// Сервис для работы с файлами проекта
@MainActor
final class FileService {
    private let logger = Logger(label: "com.supportbot.fileservice")

    /// Корневая директория проекта
    private let projectRoot: String

    /// Разрешённые расширения файлов
    private let allowedExtensions: Set<String>

    /// Максимальный размер файла для чтения (1MB)
    private let maxFileSize: Int = 1_048_576

    init(projectRoot: String, allowedExtensions: Set<String> = defaultExtensions) {
        self.projectRoot = projectRoot
        self.allowedExtensions = allowedExtensions
        logger.info("FileService initialized with root: \(projectRoot)")
    }

    /// Расширения по умолчанию
    static let defaultExtensions: Set<String> = [
        ".swift", ".md", ".txt", ".yaml", ".yml", ".json",
        ".plist", ".xcodeproj", ".pbxproj", ".sh", ".py",
        ".rb", ".js", ".ts", ".jsx", ".tsx", ".css", ".html",
        ".xml", ".graphql", ".sql", ".dockerfile", ".gitignore"
    ]

    // MARK: - Чтение файла

    /// Прочитать содержимое файла
    func readFile(path: String) throws -> String {
        let fullPath = resolvePath(path)

        guard FileManager.default.fileExists(atPath: fullPath) else {
            throw ToolError.fileNotFound(path)
        }

        // Проверяем, что это файл (не директория)
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory)
        if isDirectory.boolValue {
            return try listDirectory(path: path)
        }

        // Проверяем размер
        let attributes = try FileManager.default.attributesOfItem(atPath: fullPath)
        if let fileSize = attributes[.size] as? Int, fileSize > maxFileSize {
            throw ToolError.operationFailed("Файл слишком большой (\(fileSize / 1024)KB). Максимум: \(maxFileSize / 1024)KB")
        }

        let content = try String(contentsOfFile: fullPath, encoding: .utf8)
        logger.info("Read file: \(path) (\(content.count) characters)")

        return formatFileContent(path: path, content: content)
    }

    // MARK: - Список файлов в директории

    /// Получить список файлов в директории
    func listDirectory(path: String) throws -> String {
        let fullPath = resolvePath(path)

        guard FileManager.default.fileExists(atPath: fullPath) else {
            throw ToolError.fileNotFound(path)
        }

        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory)
        guard isDirectory.boolValue else {
            throw ToolError.invalidPath("\(path) не является директорией")
        }

        let contents = try FileManager.default.contentsOfDirectory(atPath: fullPath)
        var result = "📁 \(path)/\n\n"

        // Сортируем: директории primero, затем файлы
        var directories: [String] = []
        var files: [String] = []

        for item in contents.sorted() {
            if item.hasPrefix(".") { continue } // Скрываем скрытые файлы

            let itemPath = (fullPath as NSString).appendingPathComponent(item)
            var isItemDir: ObjCBool = false
            FileManager.default.fileExists(atPath: itemPath, isDirectory: &isItemDir)

            if isItemDir.boolValue {
                directories.append("📂 \(item)/")
            } else {
                files.append("📄 \(item)")
            }
        }

        result += directories.joined(separator: "\n")
        if !directories.isEmpty && !files.isEmpty {
            result += "\n\n"
        }
        result += files.joined(separator: "\n")

        let total = directories.count + files.count
        result += "\n\n📊 Всего: \(total) элементов (\(directories.count) директорий, \(files.count) файлов)"

        logger.info("Listed directory: \(path) (\(total) items)")
        return result
    }

    // MARK: - Поиск в файлах

    /// Поиск по содержимому файлов
    func searchInFiles(pattern: String, paths: [String] = []) async throws -> String {
        let searchPaths = paths.isEmpty ? [projectRoot] : paths.map { resolvePath($0) }
        var results: [SearchResult] = []

        for searchPath in searchPaths {
            try await searchInDirectory(path: searchPath, pattern: pattern, results: &results)
        }

        if results.isEmpty {
            return "🔍 Поиск по паттерну: `\(pattern)`\n\nНичего не найдено."
        }

        var output = "🔍 Поиск по паттерну: `\(pattern)`\n"
        output += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
        output += "Найдено совпадений: \(results.count)\n\n"

        // Группируем по файлам
        let grouped = Dictionary(grouping: results, by: { $0.file })
        for (file, matches) in grouped.sorted(by: { $0.key < $1.key }) {
            output += "📄 \(file)\n"
            output += "──────────────────────────────────────\n"
            for match in matches.prefix(10) { // Ограничиваем 10 совпадениями на файл
                output += "  \(match.lineNumber): \(match.line.trimmingCharacters(in: .whitespaces))\n"
            }
            if matches.count > 10 {
                output += "  ... и ещё \(matches.count - 10)\n"
            }
            output += "\n"
        }

        logger.info("Search completed: \(results.count) matches for pattern '\(pattern)'")
        return output
    }

    /// Поиск по glob-паттерну
    func findFiles(pattern: String, in path: String? = nil) throws -> String {
        let searchPath = path.map { resolvePath($0) } ?? projectRoot
        var foundFiles: [String] = []

        try walkDirectory(path: searchPath) { filePath in
            let relativePath = filePath.replacingOccurrences(of: projectRoot + "/", with: "")
            if matchesPattern(relativePath, pattern: pattern) {
                foundFiles.append(relativePath)
            }
        }

        if foundFiles.isEmpty {
            return "📁 Поиск по паттерну: `\(pattern)`\n\nФайлы не найдены."
        }

        var output = "📁 Поиск по паттерну: `\(pattern)`\n"
        output += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
        output += "Найдено файлов: \(foundFiles.count)\n\n"
        output += foundFiles.sorted().joined(separator: "\n")

        return output
    }

    // MARK: - Создание файла

    /// Создать новый файл
    func createFile(path: String, content: String) throws -> String {
        let fullPath = resolvePath(path)

        // Проверяем, существует ли уже файл
        if FileManager.default.fileExists(atPath: fullPath) {
            throw ToolError.operationFailed("Файл уже существует: \(path)")
        }

        // Создаём директории если нужно
        let directory = (fullPath as NSString).deletingLastPathComponent
        if !directory.isEmpty && !FileManager.default.fileExists(atPath: directory) {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }

        // Записываем файл
        try content.write(toFile: fullPath, atomically: true, encoding: .utf8)
        logger.info("Created file: \(path) (\(content.count) characters)")

        let lines = content.components(separatedBy: .newlines).count
        var output = "📝 Файл создан: `\(path)`\n"
        output += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
        output += "✅ Успешно создан\n"
        output += "📊 Статистика:\n"
        output += "  • Строк: \(lines)\n"
        output += "  • Символов: \(content.count)\n"
        output += "  • Размер: \(content.data(using: .utf8)?.count ?? 0) байт\n"

        return output
    }

    // MARK: - Изменение файла

    /// Изменить содержимое файла
    func editFile(path: String, oldContent: String, newContent: String) throws -> String {
        let fullPath = resolvePath(path)

        guard FileManager.default.fileExists(atPath: fullPath) else {
            throw ToolError.fileNotFound(path)
        }

        let currentContent = try String(contentsOfFile: fullPath, encoding: .utf8)

        guard currentContent.contains(oldContent) else {
            throw ToolError.operationFailed("Указанное содержимое не найдено в файле")
        }

        let updatedContent = currentContent.replacingOccurrences(of: oldContent, with: newContent)
        try updatedContent.write(toFile: fullPath, atomically: true, encoding: .utf8)

        let diff = generateDiff(original: oldContent, modified: newContent)
        logger.info("Edited file: \(path)")

        var output = "✏️  Файл изменён: `\(path)`\n"
        output += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
        output += "✅ Успешно изменено\n\n"
        output += "📊 Diff:\n"
        output += diff

        return output
    }

    // MARK: - Diff

    /// Сгенерировать diff между двумя версиями
    func generateDiff(original: String, modified: String) -> String {
        let originalLines = original.components(separatedBy: .newlines)
        let modifiedLines = modified.components(separatedBy: .newlines)

        var diff: [String] = []

        // Простой построчный diff
        let maxLines = max(originalLines.count, modifiedLines.count)
        for i in 0..<maxLines {
            let origLine = i < originalLines.count ? originalLines[i] : nil
            let modLine = i < modifiedLines.count ? modifiedLines[i] : nil

            if origLine != modLine {
                if let orig = origLine {
                    diff.append("- \(orig)")
                }
                if let mod = modLine {
                    diff.append("+ \(mod)")
                }
            }
        }

        if diff.isEmpty {
            return "  (без изменений)"
        }

        return diff.joined(separator: "\n")
    }

    // MARK: - Внутренние методы

    /// Разрешить путь относительно корня проекта
    private func resolvePath(_ path: String) -> String {
        if path.hasPrefix("/") {
            return path
        }
        return (projectRoot as NSString).appendingPathComponent(path)
    }

    /// Рекурсивный обход директории
    private func walkDirectory(path: String, visit: (String) throws -> Void) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return
        }

        let contents = try FileManager.default.contentsOfDirectory(atPath: path)
        for item in contents {
            if item.hasPrefix(".") { continue }

            let itemPath = (path as NSString).appendingPathComponent(item)
            var isItemDir: ObjCBool = false
            FileManager.default.fileExists(atPath: itemPath, isDirectory: &isItemDir)

            if isItemDir.boolValue {
                try walkDirectory(path: itemPath, visit: visit)
            } else {
                try visit(itemPath)
            }
        }
    }

    /// Проверка соответствия паттерну (простой glob)
    private func matchesPattern(_ filename: String, pattern: String) -> Bool {
        let regexPattern = pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*")
            .replacingOccurrences(of: "?", with: ".")
        let regex = try? NSRegularExpression(pattern: regexPattern)
        let range = NSRange(filename.startIndex..., in: filename)
        return regex?.firstMatch(in: filename, range: range) != nil
    }

    /// Поиск в директории рекурсивно
    private func searchInDirectory(path: String, pattern: String, results: inout [SearchResult]) async throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return
        }

        if !isDirectory.boolValue {
            // Это файл — ищем в нём
            try searchInFile(path: path, pattern: pattern, results: &results)
            return
        }

        let contents = try FileManager.default.contentsOfDirectory(atPath: path)
        for item in contents {
            if item.hasPrefix(".") { continue }

            let itemPath = (path as NSString).appendingPathComponent(item)
            var isItemDir: ObjCBool = false
            FileManager.default.fileExists(atPath: itemPath, isDirectory: &isItemDir)

            if isItemDir.boolValue {
                try await searchInDirectory(path: itemPath, pattern: pattern, results: &results)
            } else {
                try searchInFile(path: itemPath, pattern: pattern, results: &results)
            }
        }
    }

    /// Поиск в одном файле
    private func searchInFile(path: String, pattern: String, results: inout [SearchResult]) throws {
        let fileExtension = (path as NSString).pathExtension
        guard allowedExtensions.contains(".\(fileExtension)") || fileExtension.isEmpty else {
            return
        }

        let content = try String(contentsOfFile: path, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: pattern, options: [])
        let lines = content.components(separatedBy: .newlines)

        let relativePath = path.replacingOccurrences(of: projectRoot + "/", with: "")

        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            if regex.firstMatch(in: line, range: range) != nil {
                results.append(SearchResult(
                    file: relativePath,
                    line: line,
                    lineNumber: index + 1
                ))
            }
        }
    }

    /// Форматировать содержимое файла для вывода
    private func formatFileContent(path: String, content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        let displayLines = lines.prefix(200) // Ограничиваем вывод

        var output = "📄 \(path)\n"
        output += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        output += "📊 \(lines.count) строк, \(content.count) символов\n\n"

        for (index, line) in displayLines.enumerated() {
            output += String(format: "%4d │ %s\n", index + 1, line)
        }

        if lines.count > 200 {
            output += "\n  ... и ещё \(lines.count - 200) строк"
        }

        return output
    }
}

/// Результат поиска
struct SearchResult {
    let file: String
    let line: String
    let lineNumber: Int
}

//
//  ProjectAnalyzer.swift
//  SupportBot
//
//  Created by Stas Klem on 03.04.2026.
//

import Foundation
import Logging

/// Анализатор структуры проекта
@MainActor
final class ProjectAnalyzer {
    private let logger = Logger(label: "com.supportbot.analyzer")

    /// Корневая директория проекта
    private let projectRoot: String

    /// Файловый сервис
    private let fileService: FileService

    init(projectRoot: String, fileService: FileService) {
        self.projectRoot = projectRoot
        self.fileService = fileService
    }

    // MARK: - Анализ проекта

    /// Полный анализ структуры проекта
    func analyze() throws -> String {
        logger.info("Starting project analysis...")

        let stats = try collectStats()
        let structure = try analyzeStructure()
        let dependencies = try analyzeDependencies()

        var report = "🔬 Анализ проекта\n"
        report += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"

        // Статистика
        report += "📊 Статистика проекта:\n"
        report += "  • Всего файлов: \(stats.totalFiles)\n"
        report += "  • Строк кода: \(stats.totalLines)\n"
        report += "  • Swift файлов: \(stats.swiftFiles)\n"
        report += "  • Строк Swift: \(stats.swiftLines)\n"
        report += "  • Markdown файлов: \(stats.markdownFiles)\n"
        report += "  • Конфигурационных файлов: \(stats.configFiles)\n"
        report += "  • Размер проекта: \(formatSize(stats.totalSize))\n\n"

        // Структура
        report += "📁 Структура проекта:\n"
        report += structure + "\n\n"

        // Зависимости
        report += "🔗 Зависимости:\n"
        report += dependencies + "\n\n"

        // Рекомендации
        report += "💡 Рекомендации:\n"
        report += generateRecommendations(stats: stats)

        logger.info("Analysis complete")
        return report
    }

    // MARK: - Проверка инвариантов

    /// Проверка соответствия правилам проекта
    func checkInvariants() throws -> String {
        logger.info("Checking project invariants...")

        var results: [InvariantCheck] = []

        // 1. Наличие README
        results.append(checkFileExists(path: "README.md", name: "README.md"))

        // 2. Наличие CHANGELOG
        results.append(checkFileExists(path: "CHANGELOG.md", name: "CHANGELOG.md"))

        // 3. Наличие .gitignore
        results.append(checkFileExists(path: ".gitignore", name: ".gitignore"))

        // 4. Наличие конфигурации
        results.append(checkFileExists(path: "Config/config.yaml", name: "Config/config.yaml"))

        // 5. Наличие точки входа
        results.append(checkFileExists(path: "SupportBot/App.swift", name: "App.swift (точка входа)"))

        // 6. Наличие тестов (предупреждение)
        results.append(checkDirectoryExists(path: "Tests", name: "Tests (тесты)"))

        // 7. Наличие документации
        results.append(checkDirectoryExists(path: "KnowledgeBase", name: "KnowledgeBase (база знаний)"))

        // 8. Проверка Swift файлов на наличие @main
        results.append(checkMainEntry())

        // 9. Проверка на наличие TODO комментариев
        results.append(checkTODOs())

        // 10. Проверка лицензий
        results.append(checkLicense())

        // Формируем отчёт
        var report = "✅ Проверка инвариантов проекта\n"
        report += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"

        let passed = results.filter { $0.status == .pass }.count
        let warnings = results.filter { $0.status == .warning }.count
        let failed = results.filter { $0.status == .fail }.count

        report += "📊 Итого: \(passed) пройдено, \(warnings) предупреждений, \(failed) ошибок\n\n"

        for result in results {
            let icon: String
            switch result.status {
            case .pass: icon = "✅"
            case .warning: icon = "⚠️"
            case .fail: icon = "❌"
            }
            report += "\(icon) \(result.name)\n"
            if !result.message.isEmpty {
                report += "   \(result.message)\n"
            }
            report += "\n"
        }

        logger.info("Invariant check complete: \(passed) passed, \(warnings) warnings, \(failed) failed")
        return report
    }

    // MARK: - Поиск зависимостей

    /// Анализ зависимостей компонента
    func findComponentDependencies(componentName: String) throws -> String {
        var output = "🔍 Зависимости компонента: `\(componentName)`\n"
        output += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"

        // Ищем файлы компонента
        let swiftFiles = try findSwiftFilesContaining(pattern: componentName)

        if swiftFiles.isEmpty {
            output += "Компонент '\(componentName)' не найден в проекте.\n"
            return output
        }

        output += "Найдено в \(swiftFiles.count) файлах:\n\n"

        for file in swiftFiles {
            output += "📄 \(file)\n"

            // Ищем импорты
            let imports = try findImports(in: file)
            if !imports.isEmpty {
                output += "  Импорты: \(imports.joined(separator: ", "))\n"
            }

            // Ищем использования
            let usages = try countUsages(of: componentName, in: file)
            output += "  Использований: \(usages)\n"
            output += "\n"
        }

        return output
    }

    // MARK: - Внутренние методы

    /// Статистика проекта
    private struct ProjectStats {
        var totalFiles: Int = 0
        var totalLines: Int = 0
        var totalSize: Int = 0
        var swiftFiles: Int = 0
        var swiftLines: Int = 0
        var markdownFiles: Int = 0
        var configFiles: Int = 0
    }

    /// Сбор статистики
    private func collectStats() throws -> ProjectStats {
        var stats = ProjectStats()

        try walkDirectory(path: projectRoot) { path in
            let relativePath = path.replacingOccurrences(of: projectRoot + "/", with: "")

            // Пропускаем скрытые и build директории
            if relativePath.hasPrefix(".") || relativePath.contains(".build/") || relativePath.contains("DerivedData") {
                return
            }

            stats.totalFiles += 1

            let ext = (path as NSString).pathExtension.lowercased()

            // Считаем строки
            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                let lines = content.components(separatedBy: .newlines).count
                stats.totalLines += lines
                stats.totalSize += content.data(using: .utf8)?.count ?? 0

                switch ext {
                case "swift":
                    stats.swiftFiles += 1
                    stats.swiftLines += lines
                case "md", "markdown":
                    stats.markdownFiles += 1
                case "yaml", "yml", "json", "plist":
                    stats.configFiles += 1
                default:
                    break
                }
            }
        }

        return stats
    }

    /// Анализ структуры
    private func analyzeStructure() throws -> String {
        var tree = ""

        try buildTree(path: projectRoot, prefix: "", isLast: true, tree: &tree, maxDepth: 4)

        return tree
    }

    /// Построение дерева директорий
    private func buildTree(path: String, prefix: String, isLast: Bool, tree: inout String, maxDepth: Int, currentDepth: Int = 0) throws {
        guard currentDepth < maxDepth else { return }

        let relativePath = path.replacingOccurrences(of: projectRoot + "/", with: "")
        if relativePath.hasPrefix(".") || relativePath.contains(".build") || relativePath.contains("DerivedData") {
            return
        }

        let connector = isLast ? "└── " : "├── "
        let name = (path as NSString).lastPathComponent

        if currentDepth > 0 {
            tree += prefix + connector + name + "\n"
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return
        }

        let contents = try FileManager.default.contentsOfDirectory(atPath: path).sorted()
        let visibleContents = contents.filter { !$0.hasPrefix(".") }

        for (index, item) in visibleContents.enumerated() {
            let itemPath = (path as NSString).appendingPathComponent(item)
            let isLastItem = index == visibleContents.count - 1
            let newPrefix = currentDepth == 0 ? "" : prefix + (isLast ? "    " : "│   ")
            try buildTree(path: itemPath, prefix: newPrefix, isLast: isLastItem, tree: &tree, maxDepth: maxDepth, currentDepth: currentDepth + 1)
        }
    }

    /// Анализ зависимостей
    private func analyzeDependencies() throws -> String {
        let packageSwift = (projectRoot as NSString).appendingPathComponent("Package.swift")

        guard let content = try? String(contentsOfFile: packageSwift, encoding: .utf8) else {
            return "  Package.swift не найден\n"
        }

        var deps: [String] = []

        // Ищем строки с .package
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains(".package(") {
                // Извлекаем URL
                if let urlRange = trimmed.range(of: #"url:\s*"([^"]+)"#, options: .regularExpression) {
                    let urlMatch = trimmed[urlRange]
                    if let quoteStart = urlMatch.firstIndex(of: "\"") {
                        let quoteEnd = urlMatch.lastIndex(of: "\"")
                        if let quoteEnd = quoteEnd, quoteEnd > quoteStart {
                            let url = String(urlMatch[quoteStart...quoteEnd].dropFirst().dropLast())
                            let packageName = (url as NSString).lastPathComponent.replacingOccurrences(of: ".git", with: "")
                            deps.append(packageName)
                        }
                    }
                }
            }
        }

        if deps.isEmpty {
            return "  Зависимости не найдены\n"
        }

        return deps.map { "  • \($0)" }.joined(separator: "\n")
    }

    /// Генерация рекомендаций
    private func generateRecommendations(stats: ProjectStats) -> String {
        var recs: [String] = []

        if stats.swiftFiles < 5 {
            recs.append("  • Рассмотрите добавление модульных тестов")
        }
        if stats.markdownFiles == 0 {
            recs.append("  • Добавьте документацию в формате Markdown")
        }
        if stats.totalLines > 5000 {
            recs.append("  • Проект большой — рассмотрите разбиение на модули")
        }

        if recs.isEmpty {
            recs.append("  • Проект выглядит хорошо структурированным")
        }

        return recs.joined(separator: "\n")
    }

    /// Проверка существования файла
    private func checkFileExists(path: String, name: String) -> InvariantCheck {
        let fullPath = (projectRoot as NSString).appendingPathComponent(path)
        if FileManager.default.fileExists(atPath: fullPath) {
            return InvariantCheck(name: name, status: .pass, message: "")
        } else {
            return InvariantCheck(name: name, status: .fail, message: "Файл не найден: \(path)")
        }
    }

    /// Проверка существования директории
    private func checkDirectoryExists(path: String, name: String) -> InvariantCheck {
        let fullPath = (projectRoot as NSString).appendingPathComponent(path)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory), isDirectory.boolValue {
            return InvariantCheck(name: name, status: .pass, message: "")
        } else {
            return InvariantCheck(name: name, status: .warning, message: "Директория не найдена: \(path)")
        }
    }

    /// Проверка точки входа
    private func checkMainEntry() -> InvariantCheck {
        let appSwift = (projectRoot as NSString).appendingPathComponent("SupportBot/App.swift")
        guard let content = try? String(contentsOfFile: appSwift, encoding: .utf8) else {
            return InvariantCheck(name: "Точка входа (@main)", status: .fail, message: "App.swift не найден")
        }

        if content.contains("@main") {
            return InvariantCheck(name: "Точка входа (@main)", status: .pass, message: "")
        } else {
            return InvariantCheck(name: "Точка входа (@main)", status: .fail, message: "Не найден @main в App.swift")
        }
    }

    /// Проверка TODO комментариев
    private func checkTODOs() -> InvariantCheck {
        var todoCount = 0

        try? walkDirectory(path: projectRoot) { path in
            let ext = (path as NSString).pathExtension.lowercased()
            guard ext == "swift" else { return }

            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                let lines = content.components(separatedBy: .newlines)
                for line in lines {
                    if line.contains("TODO") || line.contains("FIXME") {
                        todoCount += 1
                    }
                }
            }
        }

        if todoCount == 0 {
            return InvariantCheck(name: "TODO комментарии", status: .pass, message: "TODO не найдены")
        } else if todoCount < 5 {
            return InvariantCheck(name: "TODO комментарии", status: .warning, message: "Найдено TODO: \(todoCount)")
        } else {
            return InvariantCheck(name: "TODO комментарии", status: .warning, message: "Много TODO: \(todoCount)")
        }
    }

    /// Проверка лицензии
    private func checkLicense() -> InvariantCheck {
        let licensePath = (projectRoot as NSString).appendingPathComponent("LICENSE")
        let readmePath = (projectRoot as NSString).appendingPathComponent("README.md")

        if FileManager.default.fileExists(atPath: licensePath) {
            return InvariantCheck(name: "Лицензия", status: .pass, message: "")
        }

        // Проверяем упоминание в README
        if let readme = try? String(contentsOfFile: readmePath, encoding: .utf8) {
            if readme.lowercased().contains("лицензи") || readme.lowercased().contains("license") {
                return InvariantCheck(name: "Лицензия", status: .warning, message: "Упоминание есть, но файл LICENSE не найден")
            }
        }

        return InvariantCheck(name: "Лицензия", status: .warning, message: "Файл LICENSE не найден")
    }

    /// Найти Swift файлы с содержимым
    private func findSwiftFilesContaining(pattern: String) throws -> [String] {
        var found: [String] = []

        try walkDirectory(path: projectRoot) { path in
            let ext = (path as NSString).pathExtension.lowercased()
            guard ext == "swift" else { return }

            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                if content.contains(pattern) {
                    let relativePath = path.replacingOccurrences(of: projectRoot + "/", with: "")
                    found.append(relativePath)
                }
            }
        }

        return found.sorted()
    }

    /// Найти импорты в файле
    private func findImports(in path: String) throws -> [String] {
        let fullPath = (projectRoot as NSString).appendingPathComponent(path)
        guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else {
            return []
        }

        var imports: [String] = []
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("import ") {
                let moduleName = trimmed.dropFirst(7).trimmingCharacters(in: .whitespaces)
                imports.append(moduleName)
            }
        }

        return imports
    }

    /// Посчитать использования строки в файле
    private func countUsages(of pattern: String, in path: String) throws -> Int {
        let fullPath = (projectRoot as NSString).appendingPathComponent(path)
        guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else {
            return 0
        }

        return content.components(separatedBy: pattern).count - 1
    }

    /// Обход директории
    private func walkDirectory(path: String, visit: (String) throws -> Void) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return
        }

        if !isDirectory.boolValue {
            try visit(path)
            return
        }

        let contents = try FileManager.default.contentsOfDirectory(atPath: path)
        for item in contents {
            let itemPath = (path as NSString).appendingPathComponent(item)
            try walkDirectory(path: itemPath, visit: visit)
        }
    }

    /// Форматирование размера
    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }
}

/// Результат проверки инварианта
struct InvariantCheck {
    let name: String
    let status: InvariantStatus
    let message: String
}

/// Статус инварианта
enum InvariantStatus {
    case pass
    case warning
    case fail
}

//
//  ConfigManager.swift
//  SupportBot
//
//  Created by Stas Klem on 02.04.2026.
//

import Foundation
import Yams
import Logging

/// Конфигурация приложения
struct AppConfig: Codable {
    let name: String
    let version: String
}

/// Конфигурация LLM
struct LLMConfig: Codable {
    let provider: String
    let apiKey: String
    let model: String
    let baseURL: String
    let timeout: Int
    
    enum CodingKeys: String, CodingKey {
        case provider
        case apiKey = "api_key"
        case model
        case baseURL = "base_url"
        case timeout
    }
}

/// Конфигурация эмбеддингов
struct EmbeddingsConfig: Codable {
    let provider: String
    let model: String
    let dimension: Int
    let baseURL: String?
    
    enum CodingKeys: String, CodingKey {
        case provider
        case model
        case dimension
        case baseURL = "base_url"
    }
}

/// Конфигурация RAG
struct RAGConfig: Codable {
    let chunkSize: Int
    let chunkOverlap: Int
    let topK: Int
    let minScore: Double
    
    enum CodingKeys: String, CodingKey {
        case chunkSize = "chunk_size"
        case chunkOverlap = "chunk_overlap"
        case topK = "top_k"
        case minScore = "min_score"
    }
}

/// Конфигурация контекста
struct ContextConfig: Codable {
    let maxHistoryMessages: Int
    let ttlSeconds: Int
    
    enum CodingKeys: String, CodingKey {
        case maxHistoryMessages = "max_history_messages"
        case ttlSeconds = "ttl_seconds"
    }
}

/// Конфигурация хранилища
struct StorageConfig: Codable {
    let databasePath: String
    let knowledgeBasePath: String
    
    enum CodingKeys: String, CodingKey {
        case databasePath = "database_path"
        case knowledgeBasePath = "knowledge_base_path"
    }
}

/// Конфигурация логирования
struct LoggingConfig: Codable {
    let level: String
    let file: String
}

/// Основная конфигурация
struct BotConfig: Codable {
    let app: AppConfig
    let llm: LLMConfig
    let embeddings: EmbeddingsConfig
    let rag: RAGConfig
    let context: ContextConfig
    let storage: StorageConfig
    let logging: LoggingConfig
}

/// Менеджер конфигурации
@MainActor
final class ConfigManager {
    static let shared = ConfigManager()
    
    private let logger = Logger(label: "com.supportbot.config")
    private var config: BotConfig?
    
    private init() {}
    
    /// Загрузка конфигурации из YAML файла
    func load(from path: String = "Config/config.yaml") throws -> BotConfig {
        if let existingConfig = config {
            return existingConfig
        }
        
        let fileURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            // Пробуем загрузить из директории приложения
            let alternativePath = "SupportBot/\(path)"
            let alternativeURL = URL(fileURLWithPath: alternativePath)
            guard FileManager.default.fileExists(atPath: alternativeURL.path) else {
                let error = ConfigError.fileNotFound(path)
                logger.error("Config file not found: \(path)")
                throw error
            }
            return try load(from: alternativePath)
        }
        
        let yamlString = try String(contentsOf: fileURL, encoding: .utf8)
        
        // Заменяем переменные окружения
        let processedYaml = try replaceEnvVariables(in: yamlString)
        
        // Парсим YAML
        let decoder = YAMLDecoder()
        let config = try decoder.decode(BotConfig.self, from: processedYaml.data(using: .utf8)!)
        self.config = config
        
        logger.info("Config loaded successfully: \(config.app.name) v\(config.app.version)")
        return config
    }
    
    /// Замена переменных окружения в YAML
    private func replaceEnvVariables(in yaml: String) throws -> String {
        var result = yaml
        let pattern = #"\$\{(\w+)\}"#
        let regex = try NSRegularExpression(pattern: pattern)
        
        let matches = regex.matches(in: yaml, range: NSRange(yaml.startIndex..., in: yaml))
        
        for match in matches.reversed() {
            guard let range = Range(match.range(at: 1), in: yaml) else { continue }
            let envVar = String(yaml[range])
            
            if let envValue = ProcessInfo.processInfo.environment[envVar] {
                guard let matchRange = Range(match.range, in: yaml) else { continue }
                result.replaceSubrange(matchRange, with: envValue)
            } else {
                logger.warning("Environment variable not found: \(envVar)")
            }
        }
        
        return result
    }
    
    /// Получить текущую конфигурацию
    func getConfig() throws -> BotConfig {
        if let config = config {
            return config
        }
        return try load()
    }
    
    /// Получить конфигурацию LLM
    func getLLMConfig() throws -> LLMConfig {
        try getConfig().llm
    }
    
    /// Получить конфигурацию RAG
    func getRAGConfig() throws -> RAGConfig {
        try getConfig().rag
    }
    
    /// Получить путь к базе данных
    func getDatabasePath() throws -> String {
        let path = try getConfig().storage.databasePath
        return expandTilde(in: path)
    }
    
    /// Получить путь к базе знаний
    func getKnowledgeBasePath() throws -> String {
        let path = try getConfig().storage.knowledgeBasePath
        return expandTilde(in: path)
    }
    
    /// Раскрытие тильды в пути
    private func expandTilde(in path: String) -> String {
        if path.hasPrefix("~/") {
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            return path.replacingCharacters(in: path.startIndex..<path.index(after: path.startIndex), with: homeDir)
        }
        return path
    }
}

enum ConfigError: LocalizedError {
    case fileNotFound(String)
    case parsingError(String)
    case missingEnvVariable(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Файл конфигурации не найден: \(path)"
        case .parsingError(let message):
            return "Ошибка парсинга конфигурации: \(message)"
        case .missingEnvVariable(let name):
            return "Переменная окружения не найдена: \(name)"
        }
    }
}

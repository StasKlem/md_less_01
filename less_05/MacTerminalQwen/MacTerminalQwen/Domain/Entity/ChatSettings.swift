//
//  ChatSettings.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

/// Entity настроек подключения к LLM API.
/// Содержит все параметры, необходимые для конфигурации запросов.
struct ChatSettings: Codable, Equatable {
    
    // MARK: - Server Configuration
    
    /// URL сервера API (например, https://api.openai.com/v1)
    var serverURL: String
    
    /// Эндпоинт для чата (обычно /chat/completions)
    var chatEndpoint: String
    
    // MARK: - Model Configuration
    
    /// Название модели (например, gpt-3.5-turbo, gpt-4)
    var modelName: String
    
    /// Температура генерации (0.0 - 2.0)
    var temperature: Double
    
    /// Максимальное количество токенов в ответе
    var maxTokens: Int?
    
    /// Top P для sampling (0.0 - 1.0)
    var topP: Double?
    
    // MARK: - Request Configuration
    
    /// Использовать потоковый режим (SSE)
    var streamEnabled: Bool
    
    /// Таймаут запроса в секундах
    var timeoutInterval: TimeInterval
    
    // MARK: - System Prompt
    
    /// Системная инструкция для модели
    var systemPrompt: String?
    
    // MARK: - Initialization
    
    init(
        serverURL: String = "",
        chatEndpoint: String = "/chat/completions",
        modelName: String = "",
        temperature: Double = 0.7,
        maxTokens: Int? = nil,
        topP: Double? = nil,
        streamEnabled: Bool = true,
        timeoutInterval: TimeInterval = 30.0,
        systemPrompt: String? = nil
    ) {
        self.serverURL = serverURL
        self.chatEndpoint = chatEndpoint
        self.modelName = modelName
        self.temperature = max(0.0, min(2.0, temperature))
        self.maxTokens = maxTokens
        self.topP = topP
        self.streamEnabled = streamEnabled
        self.timeoutInterval = timeoutInterval
        self.systemPrompt = systemPrompt
    }
    
    // MARK: - Computed Properties
    
    /// Полный URL для запросов
    var fullURL: String? {
        guard !serverURL.isEmpty else { return nil }
        
        let baseURL = serverURL.hasSuffix("/") 
            ? String(serverURL.dropLast()) 
            : serverURL
        
        let endpoint = chatEndpoint.hasPrefix("/") 
            ? chatEndpoint 
            : "/\(chatEndpoint)"
        
        return baseURL + endpoint
    }
    
    /// Проверить, заполнены ли обязательные поля
    var isValid: Bool {
        !serverURL.isEmpty && !modelName.isEmpty
    }
    
    // MARK: - Presets
    
    /// Настройки по умолчанию для OpenAI
    static let openAIDefaults = ChatSettings(
        serverURL: "https://api.openai.com/v1",
        modelName: "gpt-3.5-turbo",
        temperature: 0.7,
        streamEnabled: true
    )
    
    /// Настройки по умолчанию для локальных моделей (Ollama, LM Studio)
    static let localDefaults = ChatSettings(
        serverURL: "http://localhost:11434/v1",
        modelName: "llama-3.2",
        temperature: 0.7,
        streamEnabled: true,
        timeoutInterval: 60.0
    )
}

// MARK: - Validation

extension ChatSettings {
    
    /// Валидировать настройки и вернуть список ошибок
    func validate() -> [String] {
        var errors: [String] = []
        
        if serverURL.isEmpty {
            errors.append("URL сервера не указан")
        } else if URL(string: serverURL) == nil {
            errors.append("Некорректный URL сервера")
        }
        
        if modelName.isEmpty {
            errors.append("Название модели не указано")
        }
        
        if temperature < 0.0 || temperature > 2.0 {
            errors.append("Температура должна быть в диапазоне 0.0 - 2.0")
        }
        
        if let topP = topP, (topP < 0.0 || topP > 1.0) {
            errors.append("Top P должен быть в диапазоне 0.0 - 1.0")
        }
        
        if let maxTokens = maxTokens, maxTokens <= 0 {
            errors.append("Max tokens должен быть положительным числом")
        }
        
        return errors
    }
}

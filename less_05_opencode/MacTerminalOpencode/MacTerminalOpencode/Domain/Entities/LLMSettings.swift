//
//  LLMSettings.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

/// Configuration settings for LLM API requests
struct LLMSettings: Equatable {
    var serverURL: String
    var modelName: String
    var temperature: Double
    var maxTokens: Int
    var enableStreaming: Bool
    var systemPrompt: String
    
    init(
        serverURL: String = "http://localhost:11434/v1",
        modelName: String = "llama3.2",
        temperature: Double = 0.7,
        maxTokens: Int = 2048,
        enableStreaming: Bool = true,
        systemPrompt: String = "You are a helpful assistant."
    ) {
        self.serverURL = serverURL
        self.modelName = modelName
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.enableStreaming = enableStreaming
        self.systemPrompt = systemPrompt
    }
    
    static func == (lhs: LLMSettings, rhs: LLMSettings) -> Bool {
        lhs.serverURL == rhs.serverURL &&
        lhs.modelName == rhs.modelName &&
        lhs.temperature == rhs.temperature &&
        lhs.maxTokens == rhs.maxTokens &&
        lhs.enableStreaming == rhs.enableStreaming &&
        lhs.systemPrompt == rhs.systemPrompt
    }
}

extension LLMSettings {
    /// Returns the full chat completions endpoint URL
    var chatCompletionsURL: URL? {
        guard let baseURL = URL(string: serverURL) else { return nil }
        return baseURL.appendingPathComponent("chat/completions")
    }
    
    /// Returns the models endpoint URL
    var modelsURL: URL? {
        guard let baseURL = URL(string: serverURL) else { return nil }
        return baseURL.appendingPathComponent("models")
    }
    
    /// Validates settings and returns any errors
    func validate() -> [SettingsValidationError] {
        var errors: [SettingsValidationError] = []
        
        if serverURL.isEmpty {
            errors.append(.emptyServerURL)
        } else if URL(string: serverURL) == nil {
            errors.append(.invalidServerURL)
        }
        
        if modelName.isEmpty {
            errors.append(.emptyModelName)
        }
        
        if temperature < 0 || temperature > 2 {
            errors.append(.invalidTemperature)
        }
        
        if maxTokens < 1 {
            errors.append(.invalidMaxTokens)
        }
        
        return errors
    }
    
    var isValid: Bool {
        validate().isEmpty
    }
}

/// Validation errors for settings
enum SettingsValidationError: LocalizedError {
    case emptyServerURL
    case invalidServerURL
    case emptyModelName
    case invalidTemperature
    case invalidMaxTokens
    
    var errorDescription: String? {
        switch self {
        case .emptyServerURL:
            return "Server URL cannot be empty"
        case .invalidServerURL:
            return "Server URL is not a valid URL"
        case .emptyModelName:
            return "Model name cannot be empty"
        case .invalidTemperature:
            return "Temperature must be between 0 and 2"
        case .invalidMaxTokens:
            return "Max tokens must be at least 1"
        }
    }
}

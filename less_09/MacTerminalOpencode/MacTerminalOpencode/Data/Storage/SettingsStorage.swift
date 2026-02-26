//
//  SettingsStorage.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

/// Protocol for settings storage operations
protocol SettingsStorageProtocol {
    func loadSettings() -> LLMSettings
    func saveSettings(_ settings: LLMSettings)
}

/// Manages persistent storage of application settings via UserDefaults
final class SettingsStorage: SettingsStorageProtocol {
    
    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    private enum Keys {
        static let serverURL = "llm.settings.serverURL"
        static let modelName = "llm.settings.modelName"
        static let temperature = "llm.settings.temperature"
        static let maxTokens = "llm.settings.maxTokens"
        static let enableStreaming = "llm.settings.enableStreaming"
        static let systemPrompt = "llm.settings.systemPrompt"
        static let saveContext = "llm.settings.saveContext"
    }
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }
    
    /// Loads settings from UserDefaults, returns defaults if not found
    func loadSettings() -> LLMSettings {
        LLMSettings(
            serverURL: defaults.string(forKey: Keys.serverURL) ?? "http://localhost:11434/v1",
            modelName: defaults.string(forKey: Keys.modelName) ?? "llama3.2",
            temperature: defaults.double(forKey: Keys.temperature) == 0 ? 0.7 : defaults.double(forKey: Keys.temperature),
            maxTokens: defaults.integer(forKey: Keys.maxTokens) == 0 ? 2048 : defaults.integer(forKey: Keys.maxTokens),
            enableStreaming: defaults.object(forKey: Keys.enableStreaming) as? Bool ?? true,
            systemPrompt: defaults.string(forKey: Keys.systemPrompt) ?? "You are a helpful assistant.",
            saveContext: defaults.object(forKey: Keys.saveContext) as? Bool ?? false
        )
    }
    
    /// Saves settings to UserDefaults
    func saveSettings(_ settings: LLMSettings) {
        defaults.set(settings.serverURL, forKey: Keys.serverURL)
        defaults.set(settings.modelName, forKey: Keys.modelName)
        defaults.set(settings.temperature, forKey: Keys.temperature)
        defaults.set(settings.maxTokens, forKey: Keys.maxTokens)
        defaults.set(settings.enableStreaming, forKey: Keys.enableStreaming)
        defaults.set(settings.systemPrompt, forKey: Keys.systemPrompt)
        defaults.set(settings.saveContext, forKey: Keys.saveContext)
        defaults.synchronize()
    }
    
    /// Clears all stored settings
    func clearSettings() {
        defaults.removeObject(forKey: Keys.serverURL)
        defaults.removeObject(forKey: Keys.modelName)
        defaults.removeObject(forKey: Keys.temperature)
        defaults.removeObject(forKey: Keys.maxTokens)
        defaults.removeObject(forKey: Keys.enableStreaming)
        defaults.removeObject(forKey: Keys.systemPrompt)
        defaults.removeObject(forKey: Keys.saveContext)
        defaults.synchronize()
    }
}

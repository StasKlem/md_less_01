//
//  UserDefaultsStorage.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

/// Протокол хранилища настроек в UserDefaults.
protocol UserDefaultsStorageProtocol {
    /// Сохранить настройки
    func saveSettings(_ settings: ChatSettings) throws
    
    /// Загрузить настройки
    func loadSettings() -> ChatSettings?
    
    /// Удалить сохранённые настройки
    func clearSettings() throws
    
    /// Получить или создать настройки по умолчанию
    func getOrCreateDefaults() -> ChatSettings
}

/// Реализация хранилища настроек в UserDefaults.
final class UserDefaultsStorage: UserDefaultsStorageProtocol {
    
    // MARK: - Keys
    
    private enum Keys {
        static let serverURL = "serverURL"
        static let chatEndpoint = "chatEndpoint"
        static let modelName = "modelName"
        static let temperature = "temperature"
        static let maxTokens = "maxTokens"
        static let topP = "topP"
        static let streamEnabled = "streamEnabled"
        static let timeoutInterval = "timeoutInterval"
        static let systemPrompt = "systemPrompt"
    }
    
    // MARK: - Properties
    
    private let userDefaults: UserDefaults
    private let suiteName: String
    
    // MARK: - Initialization
    
    init(
        suiteName: String = "StasKlem.MacTerminalQwen",
        userDefaults: UserDefaults = .standard
    ) {
        self.suiteName = suiteName
        self.userDefaults = userDefaults
    }
    
    // MARK: - UserDefaultsStorageProtocol
    
    func saveSettings(_ settings: ChatSettings) throws {
        userDefaults.set(settings.serverURL, forKey: Keys.serverURL)
        userDefaults.set(settings.chatEndpoint, forKey: Keys.chatEndpoint)
        userDefaults.set(settings.modelName, forKey: Keys.modelName)
        userDefaults.set(settings.temperature, forKey: Keys.temperature)
        userDefaults.set(settings.maxTokens, forKey: Keys.maxTokens)
        userDefaults.set(settings.topP, forKey: Keys.topP)
        userDefaults.set(settings.streamEnabled, forKey: Keys.streamEnabled)
        userDefaults.set(settings.timeoutInterval, forKey: Keys.timeoutInterval)
        userDefaults.set(settings.systemPrompt, forKey: Keys.systemPrompt)
        
        // Синхронизация
        userDefaults.synchronize()
    }
    
    func loadSettings() -> ChatSettings? {
        // Проверка наличия сохранённых данных
        guard let serverURL = userDefaults.string(forKey: Keys.serverURL),
              !serverURL.isEmpty else {
            return nil
        }
        
        let settings = ChatSettings(
            serverURL: serverURL,
            chatEndpoint: userDefaults.string(forKey: Keys.chatEndpoint) ?? "/chat/completions",
            modelName: userDefaults.string(forKey: Keys.modelName) ?? "",
            temperature: userDefaults.double(forKey: Keys.temperature),
            maxTokens: userDefaults.object(forKey: Keys.maxTokens) as? Int,
            topP: userDefaults.object(forKey: Keys.topP) as? Double,
            streamEnabled: userDefaults.object(forKey: Keys.streamEnabled) as? Bool ?? true,
            timeoutInterval: userDefaults.double(forKey: Keys.timeoutInterval),
            systemPrompt: userDefaults.string(forKey: Keys.systemPrompt)
        )
        
        return settings
    }
    
    func clearSettings() throws {
        userDefaults.removeObject(forKey: Keys.serverURL)
        userDefaults.removeObject(forKey: Keys.chatEndpoint)
        userDefaults.removeObject(forKey: Keys.modelName)
        userDefaults.removeObject(forKey: Keys.temperature)
        userDefaults.removeObject(forKey: Keys.maxTokens)
        userDefaults.removeObject(forKey: Keys.topP)
        userDefaults.removeObject(forKey: Keys.streamEnabled)
        userDefaults.removeObject(forKey: Keys.timeoutInterval)
        userDefaults.removeObject(forKey: Keys.systemPrompt)
        
        userDefaults.synchronize()
    }
}

// MARK: - Convenience Methods

extension UserDefaultsStorage {
    
    /// Получить или создать настройки по умолчанию
    func getOrCreateDefaults() -> ChatSettings {
        if let existing = loadSettings() {
            return existing
        }
        
        let defaults = ChatSettings.localDefaults
        try? saveSettings(defaults)
        return defaults
    }
    
    /// Обновить отдельное поле настроек
    func updateField(_ field: KeyPath<ChatSettings, String>, value: String) throws {
        var settings = getOrCreateDefaults()
        
        switch field {
        case \ChatSettings.serverURL:
            settings.serverURL = value
        case \ChatSettings.chatEndpoint:
            settings.chatEndpoint = value
        case \ChatSettings.modelName:
            settings.modelName = value
        default:
            break
        }
        
        try saveSettings(settings)
    }
    
    /// Обновить отдельное поле настроек (Double)
    func updateField(_ field: KeyPath<ChatSettings, Double>, value: Double) throws {
        var settings = getOrCreateDefaults()
        
        switch field {
        case \ChatSettings.temperature:
            settings.temperature = value
        case \ChatSettings.topP:
            settings.topP = value
        default:
            break
        }
        
        try saveSettings(settings)
    }
    
    /// Обновить отдельное поле настроек (Int?)
    func updateField(_ field: KeyPath<ChatSettings, Int?>, value: Int?) throws {
        var settings = getOrCreateDefaults()
        
        switch field {
        case \ChatSettings.maxTokens:
            settings.maxTokens = value
        default:
            break
        }
        
        try saveSettings(settings)
    }
    
    /// Обновить отдельное поле настроек (Bool)
    func updateField(_ field: KeyPath<ChatSettings, Bool>, value: Bool) throws {
        var settings = getOrCreateDefaults()
        
        switch field {
        case \ChatSettings.streamEnabled:
            settings.streamEnabled = value
        default:
            break
        }
        
        try saveSettings(settings)
    }
}

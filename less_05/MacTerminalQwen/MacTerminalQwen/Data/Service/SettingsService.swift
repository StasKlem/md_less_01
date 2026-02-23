//
//  SettingsService.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation
import Combine

/// Сервис для управления настройками приложения.
/// Содержит все настраиваемые параметры и обеспечивает их сохранение/загрузку.
final actor SettingsService {
    
    // MARK: - Published Properties
    
    /// URL сервера API
    @Published var serverURL: String = ""
    
    /// Эндпоинт чата
    @Published var chatEndpoint: String = "/chat/completions"
    
    /// Название модели
    @Published var modelName: String = ""
    
    /// Температура генерации (0.0 - 2.0)
    @Published var temperature: Double = 0.7
    
    /// Максимальное количество токенов
    @Published var maxTokens: Int? = nil
    
    /// Top P для sampling (0.0 - 1.0)
    @Published var topP: Double? = nil
    
    /// Включить потоковый режим
    @Published var streamEnabled: Bool = true
    
    /// Таймаут запроса в секундах
    @Published var timeoutInterval: TimeInterval = 30.0
    
    /// Системная инструкция
    @Published var systemPrompt: String = ""
    
    // MARK: - Private Properties
    
    private let userDefaults: UserDefaults
    private let keychain: KeychainStorageProtocol
    private let settingsKey: String = "StasKlem.MacTerminalQwen.Settings"
    
    // MARK: - Initialization
    
    init(
        userDefaults: UserDefaults = .standard,
        keychain: KeychainStorageProtocol = KeychainStorage()
    ) {
        self.userDefaults = userDefaults
        self.keychain = keychain
        load()
    }
    
    // MARK: - Public Methods
    
    /// Загрузить настройки из хранилища
    func load() {
        // Загрузка из UserDefaults
        if let data = userDefaults.data(forKey: settingsKey),
           let settings = try? JSONDecoder().decode(SettingsData.self, from: data) {
            serverURL = settings.serverURL
            chatEndpoint = settings.chatEndpoint
            modelName = settings.modelName
            temperature = settings.temperature
            maxTokens = settings.maxTokens
            topP = settings.topP
            streamEnabled = settings.streamEnabled
            timeoutInterval = settings.timeoutInterval
            systemPrompt = settings.systemPrompt ?? ""
        } else {
            // Настройки по умолчанию
            applyDefaults()
        }
    }
    
    /// Сохранить настройки в хранилище
    func save() throws {
        let settings = SettingsData(
            serverURL: serverURL,
            chatEndpoint: chatEndpoint,
            modelName: modelName,
            temperature: temperature,
            maxTokens: maxTokens,
            topP: topP,
            streamEnabled: streamEnabled,
            timeoutInterval: timeoutInterval,
            systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt
        )
        
        let data = try JSONEncoder().encode(settings)
        userDefaults.set(data, forKey: settingsKey)
        userDefaults.synchronize()
    }
    
    /// Сохранить API Key в Keychain
    func saveAPIKey(_ apiKey: String) throws {
        try keychain.save(apiKey, forKey: "api_key")
    }
    
    /// Загрузить API Key из Keychain
    func loadAPIKey() throws -> String? {
        try keychain.load(forKey: "api_key")
    }
    
    /// Удалить API Key
    func deleteAPIKey() throws {
        try keychain.delete(forKey: "api_key")
    }
    
    /// Проверить наличие API Key
    func hasAPIKey() -> Bool {
        (try? loadAPIKey()) != nil
    }
    
    /// Сбросить настройки к значениям по умолчанию
    func resetToDefaults() {
        applyDefaults()
        try? save()
    }
    
    /// Получить текущие настройки как ChatSettings
    func getChatSettings() -> ChatSettings {
        ChatSettings(
            serverURL: serverURL,
            chatEndpoint: chatEndpoint,
            modelName: modelName,
            temperature: temperature,
            maxTokens: maxTokens,
            topP: topP,
            streamEnabled: streamEnabled,
            timeoutInterval: timeoutInterval,
            systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt
        )
    }
    
    /// Обновить настройки из ChatSettings
    func update(from settings: ChatSettings) {
        serverURL = settings.serverURL
        chatEndpoint = settings.chatEndpoint
        modelName = settings.modelName
        temperature = settings.temperature
        maxTokens = settings.maxTokens
        topP = settings.topP
        streamEnabled = settings.streamEnabled
        timeoutInterval = settings.timeoutInterval
        systemPrompt = settings.systemPrompt ?? ""
    }
    
    // MARK: - Private Methods
    
    private func applyDefaults() {
        serverURL = "http://localhost:11434/v1"
        chatEndpoint = "/chat/completions"
        modelName = "llama-3.2"
        temperature = 0.7
        maxTokens = nil
        topP = nil
        streamEnabled = true
        timeoutInterval = 60.0
        systemPrompt = ""
    }
}

// MARK: - Private Data Structure

private extension SettingsService {
    struct SettingsData: Codable {
        var serverURL: String
        var chatEndpoint: String
        var modelName: String
        var temperature: Double
        var maxTokens: Int?
        var topP: Double?
        var streamEnabled: Bool
        var timeoutInterval: TimeInterval
        var systemPrompt: String?
    }
}

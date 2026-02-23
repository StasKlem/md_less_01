//
//  SettingsFormService.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

/// Сервис для хранения данных формы настроек.
/// Предоставляет простой API для получения и сохранения настроек.
final class SettingsFormService {
    
    // MARK: - Properties
    
    /// URL сервера API
    var serverURL: String = ""
    
    /// Эндпоинт чата
    var chatEndpoint: String = "/chat/completions"
    
    /// Название модели
    var modelName: String = ""
    
    /// Температура генерации (0.0 - 2.0)
    var temperature: Double = 0.7
    
    /// Максимальное количество токенов
    var maxTokens: String = ""
    
    /// Top P для sampling (0.0 - 1.0)
    var topP: String = ""
    
    /// Включить потоковый режим
    var streamEnabled: Bool = true
    
    /// Таймаут запроса в секундах
    var timeoutInterval: Double = 30.0
    
    /// Системная инструкция
    var systemPrompt: String = ""
    
    /// API Key (для отображения в UI)
    var apiKeyInput: String = ""
    
    /// Индикатор наличия сохранённого API Key
    var hasAPIKey: Bool = false
    
    // MARK: - Private Properties
    
    private let settingsService: SettingsService
    
    // MARK: - Initialization
    
    init(settingsService: SettingsService) {
        self.settingsService = settingsService
        loadFromSettingsServiceSync()
    }
    
    // MARK: - Public Methods
    
    /// Загрузить данные из SettingsService (синхронная версия для init)
    private func loadFromSettingsServiceSync() {
        // Используем значения по умолчанию
        serverURL = "http://localhost:11434/v1"
        chatEndpoint = "/chat/completions"
        modelName = "llama-3.2"
        temperature = 0.7
        maxTokens = ""
        topP = ""
        streamEnabled = true
        timeoutInterval = 60.0
        systemPrompt = ""
        hasAPIKey = false
        apiKeyInput = ""
    }
    
    /// Загрузить данные из SettingsService
    func loadFromSettingsService() async {
        let settings = await settingsService.getChatSettings()
        
        serverURL = settings.serverURL
        chatEndpoint = settings.chatEndpoint
        modelName = settings.modelName
        temperature = settings.temperature
        maxTokens = settings.maxTokens.map(String.init) ?? ""
        topP = settings.topP.map { String(format: "%.2f", $0) } ?? ""
        streamEnabled = settings.streamEnabled
        timeoutInterval = settings.timeoutInterval
        systemPrompt = settings.systemPrompt ?? ""
        
        let apiKey = (try? await settingsService.loadAPIKey()) ?? ""
        hasAPIKey = !apiKey.isEmpty
        apiKeyInput = ""
    }
    
    /// Сохранить данные в SettingsService
    func saveToSettingsService() async throws -> Bool {
        // Валидация числовых полей
        if !maxTokens.isEmpty && Int(maxTokens) == nil {
            throw SettingsFormError.invalidMaxTokens
        }
        
        if !topP.isEmpty && (Double(topP) ?? -1) < 0 || (Double(topP) ?? 101) > 1 {
            throw SettingsFormError.invalidTopP
        }
        
        let settings = ChatSettings(
            serverURL: serverURL,
            chatEndpoint: chatEndpoint,
            modelName: modelName,
            temperature: temperature,
            maxTokens: Int(maxTokens),
            topP: Double(topP),
            streamEnabled: streamEnabled,
            timeoutInterval: timeoutInterval,
            systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt
        )
        
        await settingsService.update(from: settings)
        try await settingsService.save()
        
        return true
    }
    
    /// Сохранить API Key
    func saveAPIKey() async throws {
        let trimmedKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedKey.isEmpty else {
            try await settingsService.deleteAPIKey()
            hasAPIKey = false
            apiKeyInput = ""
            return
        }
        
        try await settingsService.saveAPIKey(trimmedKey)
        hasAPIKey = true
        apiKeyInput = ""
    }
    
    /// Сбросить к значениям по умолчанию
    func resetToDefaults() {
        serverURL = "http://localhost:11434/v1"
        chatEndpoint = "/chat/completions"
        modelName = "llama-3.2"
        temperature = 0.7
        maxTokens = ""
        topP = ""
        streamEnabled = true
        timeoutInterval = 60.0
        systemPrompt = ""
    }
    
    /// Проверить валидность настроек
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
        
        if !maxTokens.isEmpty, let maxTokens = Int(maxTokens), maxTokens <= 0 {
            errors.append("Max tokens должен быть положительным числом")
        }
        
        if !topP.isEmpty, let topP = Double(topP), (topP < 0.0 || topP > 1.0) {
            errors.append("Top P должен быть в диапазоне 0.0 - 1.0")
        }
        
        return errors
    }
}

// MARK: - Errors

enum SettingsFormError: LocalizedError {
    case invalidMaxTokens
    case invalidTopP
    
    var errorDescription: String? {
        switch self {
        case .invalidMaxTokens:
            return "Max tokens должен быть целым числом"
        case .invalidTopP:
            return "Top P должен быть числом от 0.0 до 1.0"
        }
    }
}

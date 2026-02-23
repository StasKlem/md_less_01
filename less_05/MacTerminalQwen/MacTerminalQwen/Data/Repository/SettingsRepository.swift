//
//  SettingsRepository.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation
import Combine

/// Протокол репозитория для работы с настройками.
protocol SettingsRepositoryProtocol {
    /// Загрузить настройки
    func loadSettings() -> ChatSettings
    
    /// Сохранить настройки
    func saveSettings(_ settings: ChatSettings) throws
    
    /// Загрузить API Key
    func loadAPIKey() throws -> String?
    
    /// Сохранить API Key
    func saveAPIKey(_ apiKey: String) throws
    
    /// Удалить API Key
    func deleteAPIKey() throws
    
    /// Проверить наличие API Key
    func hasAPIKey() -> Bool
    
    /// Получить настройки и API Key
    func getCompleteSettings() throws -> (settings: ChatSettings, apiKey: String?)
}

/// Реализация репозитория для работы с настройками.
final class SettingsRepository: SettingsRepositoryProtocol {
    
    // MARK: - Properties
    
    private let userDefaultsStorage: UserDefaultsStorageProtocol
    private let keychainStorage: KeychainStorageProtocol
    
    // MARK: - Initialization
    
    init(
        userDefaultsStorage: UserDefaultsStorageProtocol = UserDefaultsStorage(),
        keychainStorage: KeychainStorageProtocol = KeychainStorage()
    ) {
        self.userDefaultsStorage = userDefaultsStorage
        self.keychainStorage = keychainStorage
    }
    
    // MARK: - SettingsRepositoryProtocol
    
    func loadSettings() -> ChatSettings {
        userDefaultsStorage.getOrCreateDefaults()
    }
    
    func saveSettings(_ settings: ChatSettings) throws {
        try userDefaultsStorage.saveSettings(settings)
    }
    
    func loadAPIKey() throws -> String? {
        try keychainStorage.loadAPIKey()
    }
    
    func saveAPIKey(_ apiKey: String) throws {
        try keychainStorage.saveAPIKey(apiKey)
    }
    
    func deleteAPIKey() throws {
        try keychainStorage.deleteAPIKey()
    }
    
    func hasAPIKey() -> Bool {
        keychainStorage.hasAPIKey()
    }
    
    func getCompleteSettings() throws -> (settings: ChatSettings, apiKey: String?) {
        let settings = loadSettings()
        let apiKey = try loadAPIKey()
        return (settings, apiKey)
    }
}

// MARK: - Reactive Settings

extension SettingsRepository {
    
    /// Создать Publisher для наблюдения за изменениями настроек
    func settingsPublisher() -> AnyPublisher<ChatSettings, Never> {
        // В простой реализации возвращаем текущие настройки
        // Для полноценного наблюдения можно использовать NotificationCenter
        Just(loadSettings()).eraseToAnyPublisher()
    }
    
    /// Создать Publisher для наблюдения за наличием API Key
    func apiKeyStatusPublisher() -> AnyPublisher<Bool, Never> {
        Just(hasAPIKey()).eraseToAnyPublisher()
    }
}

// MARK: - Validation Helper

extension SettingsRepository {
    
    /// Валидировать и сохранить настройки
    func validateAndSave(_ settings: ChatSettings) -> ValidationResult {
        let validator = ValidateSettingsUseCase()
        let result = validator.execute(settings: settings)
        
        if result.isValid {
            try? saveSettings(settings)
        }
        
        return result
    }
}

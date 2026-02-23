//
//  KeychainStorage.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation
import Security

/// Протокол безопасного хранилища в Keychain.
protocol KeychainStorageProtocol {
    /// Сохранить секретное значение
    func save(_ value: String, forKey key: String) throws
    
    /// Загрузить секретное значение
    func load(forKey key: String) throws -> String?
    
    /// Удалить секретное значение
    func delete(forKey key: String) throws
    
    /// Очистить все сохранённые значения
    func clearAll() throws
    
    /// Сохранить API Key
    func saveAPIKey(_ apiKey: String) throws
    
    /// Загрузить API Key
    func loadAPIKey() throws -> String?
    
    /// Удалить API Key
    func deleteAPIKey() throws
    
    /// Проверить наличие API Key
    func hasAPIKey() -> Bool
}

/// Ошибки Keychain
enum KeychainError: LocalizedError {
    case duplicateEntry
    case notFound
    case conversionError
    case unhandledError(OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .duplicateEntry:
            return "Запись уже существует"
        case .notFound:
            return "Запись не найдена"
        case .conversionError:
            return "Ошибка преобразования данных"
        case .unhandledError(let status):
            return "Ошибка Keychain: \(status)"
        }
    }
}

/// Реализация хранилища в macOS Keychain.
final class KeychainStorage: KeychainStorageProtocol {
    
    // MARK: - Keys
    
    enum Key {
        static let apiKey = "llm_api_key"
    }
    
    // MARK: - Properties
    
    private let serviceName: String
    private let accessGroup: String?
    
    // MARK: - Initialization
    
    init(
        serviceName: String = "StasKlem.MacTerminalQwen",
        accessGroup: String? = nil
    ) {
        self.serviceName = serviceName
        self.accessGroup = accessGroup
    }
    
    // MARK: - KeychainStorageProtocol
    
    func save(_ value: String, forKey key: String) throws {
        // Попытка обновить существующую запись
        do {
            try update(value, forKey: key)
            return
        } catch KeychainError.notFound {
            // Запись не найдена, создаём новую
        }
        
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.conversionError
        }
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status)
        }
    }
    
    func load(forKey key: String) throws -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status != errSecItemNotFound else {
            return nil
        }
        
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status)
        }
        
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.conversionError
        }
        
        return value
    }
    
    func delete(forKey key: String) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status != errSecItemNotFound else {
            throw KeychainError.notFound
        }
        
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status)
        }
    }
    
    func clearAll() throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        let status = SecItemDelete(query as CFDictionary)
        
        // Игнорируем notFound, если ничего нет для удаления
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status)
        }
    }
    
    // MARK: - Private
    
    private func update(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.conversionError
        }
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        guard status != errSecItemNotFound else {
            throw KeychainError.notFound
        }
        
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status)
        }
    }
}

// MARK: - Convenience Methods

extension KeychainStorage {
    
    /// Сохранить API Key
    func saveAPIKey(_ apiKey: String) throws {
        try save(apiKey, forKey: Key.apiKey)
    }
    
    /// Загрузить API Key
    func loadAPIKey() throws -> String? {
        try load(forKey: Key.apiKey)
    }
    
    /// Удалить API Key
    func deleteAPIKey() throws {
        try delete(forKey: Key.apiKey)
    }
    
    /// Проверить наличие API Key
    func hasAPIKey() -> Bool {
        (try? loadAPIKey()) != nil
    }
}

// MARK: - AppError Conversion

extension AppError {
    static func fromKeychainError(_ error: Error) -> AppError {
        if let keychainError = error as? KeychainError {
            return .keychain(keychainError.errorDescription ?? "Unknown Keychain error")
        }
        return .keychain(error.localizedDescription)
    }
}

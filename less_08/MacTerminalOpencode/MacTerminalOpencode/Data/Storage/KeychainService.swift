//
//  KeychainService.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation
import Security

/// Protocol for secure storage operations
protocol KeychainServiceProtocol {
    func saveAPIKey(_ key: String) throws
    func loadAPIKey() throws -> String?
    func deleteAPIKey() throws
}

/// Provides secure storage for sensitive data like API keys using Keychain
final class KeychainService: KeychainServiceProtocol {
    
    private let service: String
    
    private enum Keys {
        static let apiKey = "llm.api.key"
    }
    
    init(service: String = "com.stasklem.MacTerminalOpencode") {
        self.service = service
    }
    
    /// Saves API key to Keychain
    func saveAPIKey(_ key: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw AppError.storage(.keychainWriteFailed)
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Keys.apiKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        let status: OSStatus
        
        if let _ = try? loadAPIKeyData() {
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: Keys.apiKey
            ]
            let updateAttributes: [String: Any] = [
                kSecValueData as String: data
            ]
            status = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
        } else {
            status = SecItemAdd(query as CFDictionary, nil)
        }
        
        guard status == errSecSuccess else {
            throw AppError.storage(.keychainWriteFailed)
        }
    }
    
    /// Loads API key from Keychain
    func loadAPIKey() throws -> String? {
        guard let data = try loadAPIKeyData() else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    
    /// Deletes API key from Keychain
    func deleteAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Keys.apiKey
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.storage(.keychainDeleteFailed)
        }
    }
    
    private func loadAPIKeyData() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Keys.apiKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw AppError.storage(.keychainReadFailed)
        }
        
        return result as? Data
    }
}

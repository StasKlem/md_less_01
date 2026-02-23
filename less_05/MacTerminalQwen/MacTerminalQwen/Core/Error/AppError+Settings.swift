//
//  AppError+Settings.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

extension AppError {
    static func fromSettingsError(_ error: Error) -> AppError {
        if let keychainError = error as? KeychainError {
            return .keychain(keychainError.errorDescription ?? "Unknown Keychain error")
        } else {
            return .unknown(error)
        }
    }
}

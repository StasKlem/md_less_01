//
//  AppError.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

/// Unified error type for the application
enum AppError: LocalizedError, Equatable {
    case network(NetworkError)
    case storage(StorageError)
    case validation(SettingsValidationError)
    case parsing(ParsingError)
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .network(let error):
            return error.errorDescription
        case .storage(let error):
            return error.errorDescription
        case .validation(let error):
            return error.errorDescription
        case .parsing(let error):
            return error.errorDescription
        case .unknown(let message):
            return message
        }
    }
    
    static func == (lhs: AppError, rhs: AppError) -> Bool {
        lhs.errorDescription == rhs.errorDescription
    }
}

enum NetworkError: LocalizedError {
    case invalidURL
    case noConnection
    case timeout
    case httpError(statusCode: Int, message: String?)
    case unauthorized
    case serverError(String)
    case noData
    case streamingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .noConnection:
            return "No network connection available"
        case .timeout:
            return "Request timed out"
        case .httpError(let statusCode, let message):
            return "HTTP Error \(statusCode): \(message ?? "Unknown error")"
        case .unauthorized:
            return "Invalid or missing API key"
        case .serverError(let message):
            return "Server error: \(message)"
        case .noData:
            return "No data received from server"
        case .streamingFailed(let message):
            return "Streaming failed: \(message)"
        }
    }
}

enum StorageError: LocalizedError {
    case keychainReadFailed
    case keychainWriteFailed
    case keychainDeleteFailed
    case userDefaultsReadFailed
    
    var errorDescription: String? {
        switch self {
        case .keychainReadFailed:
            return "Failed to read from secure storage"
        case .keychainWriteFailed:
            return "Failed to write to secure storage"
        case .keychainDeleteFailed:
            return "Failed to delete from secure storage"
        case .userDefaultsReadFailed:
            return "Failed to read settings"
        }
    }
}

enum ParsingError: LocalizedError {
    case invalidJSON
    case invalidSSEFormat
    case missingRequiredField(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "Invalid JSON response"
        case .invalidSSEFormat:
            return "Invalid streaming data format"
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        }
    }
}

//
//  EmbeddingModel.swift
//  SupportBot
//
//  Created by Stas Klem on 02.04.2026.
//

import Foundation

/// Протокол модели эмбеддингов
@MainActor
protocol EmbeddingModel {
    /// Название модели
    var modelName: String { get }
    
    /// Размерность вектора
    var dimension: Int { get }
    
    /// Создать эмбеддинг для текста
    func embed(text: String) async throws -> [Double]
    
    /// Создать эмбеддинги для нескольких текстов
    func embed(texts: [String]) async throws -> [[Double]]
}

/// Ошибка embedding
enum EmbeddingError: LocalizedError {
    case apiError(String)
    case parsingError(String)
    case networkError(String)
    case invalidResponse(String)
    
    var errorDescription: String? {
        switch self {
        case .apiError(let message):
            return "Ошибка API эмбеддингов: \(message)"
        case .parsingError(let message):
            return "Ошибка парсинга: \(message)"
        case .networkError(let message):
            return "Ошибка сети: \(message)"
        case .invalidResponse(let message):
            return "Неверный ответ: \(message)"
        }
    }
}

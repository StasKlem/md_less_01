//
//  ValidateSettingsUseCase.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

/// Результат валидации настроек.
struct ValidationResult: Equatable {
    /// Успешна ли валидация
    let isValid: Bool
    
    /// Список ошибок
    let errors: [String]
    
    /// Список предупреждений
    let warnings: [String]
    
    static let success = ValidationResult(isValid: true, errors: [], warnings: [])
    
    static func failure(_ errors: [String], warnings: [String] = []) -> ValidationResult {
        ValidationResult(isValid: false, errors: errors, warnings: warnings)
    }
}

/// Use Case для валидации настроек API.
/// Проверяет корректность данных перед сохранением и использованием.
protocol ValidateSettingsUseCaseProtocol {
    /// Валидировать настройки
    /// - Parameter settings: Настройки для проверки
    /// - Returns: Результат валидации
    func execute(settings: ChatSettings) -> ValidationResult
    
    /// Валидировать URL сервера
    /// - Parameter url: URL для проверки
    /// - Returns: Результат валидации
    func validateURL(_ url: String) -> ValidationResult
    
    /// Валидировать название модели
    /// - Parameter modelName: Название модели
    /// - Returns: Результат валидации
    func validateModelName(_ modelName: String) -> ValidationResult
    
    /// Валидировать температуру
    /// - Parameter temperature: Значение температуры
    /// - Returns: Результат валидации
    func validateTemperature(_ temperature: Double) -> ValidationResult
}

/// Реализация Use Case для валидации настроек.
final class ValidateSettingsUseCase: ValidateSettingsUseCaseProtocol {
    
    // MARK: - ValidateSettingsUseCaseProtocol
    
    func execute(settings: ChatSettings) -> ValidationResult {
        var errors: [String] = []
        var warnings: [String] = []
        
        // Валидация URL
        let urlResult = validateURL(settings.serverURL)
        if !urlResult.isValid {
            errors.append(contentsOf: urlResult.errors)
        }
        
        // Валидация модели
        let modelResult = validateModelName(settings.modelName)
        if !modelResult.isValid {
            errors.append(contentsOf: modelResult.errors)
        }
        
        // Валидация температуры
        let tempResult = validateTemperature(settings.temperature)
        if !tempResult.isValid {
            errors.append(contentsOf: tempResult.errors)
        }
        warnings.append(contentsOf: tempResult.warnings)
        
        // Валидация topP
        if let topP = settings.topP {
            if topP < 0.0 || topP > 1.0 {
                errors.append("Top P должен быть в диапазоне 0.0 - 1.0")
            }
        }
        
        // Валидация maxTokens
        if let maxTokens = settings.maxTokens {
            if maxTokens <= 0 {
                errors.append("Max tokens должен быть положительным числом")
            } else if maxTokens > 32000 {
                warnings.append("Большие значения max tokens могут привести к ошибкам")
            }
        }
        
        // Валидация timeout
        if settings.timeoutInterval < 5.0 {
            warnings.append("Маленький таймаут может привести к обрыву соединения")
        }
        
        if errors.isEmpty {
            return ValidationResult(isValid: true, errors: [], warnings: warnings)
        } else {
            return ValidationResult(isValid: false, errors: errors, warnings: warnings)
        }
    }
    
    func validateURL(_ url: String) -> ValidationResult {
        if url.isEmpty {
            return .failure(["URL сервера не может быть пустым"])
        }
        
        // Проверка формата URL
        guard let components = URLComponents(string: url),
              let scheme = components.scheme,
              let host = components.host else {
            return .failure(["Некорректный формат URL"])
        }
        
        // Проверка схемы
        guard ["http", "https"].contains(scheme) else {
            return .failure(["URL должен использовать схему http или https"])
        }
        
        // Предупреждение для HTTP
        if scheme == "http" {
            return ValidationResult(
                isValid: true,
                errors: [],
                warnings: ["Используется незащищённое HTTP-соединение"]
            )
        }
        
        return .success
    }
    
    func validateModelName(_ modelName: String) -> ValidationResult {
        if modelName.isEmpty {
            return .failure(["Название модели не может быть пустым"])
        }
        
        // Проверка на допустимые символы
        let allowedCharacters = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-_."))
        
        if modelName.unicodeScalars.contains(where: { !allowedCharacters.contains($0) }) {
            return .failure(["Название модели содержит недопустимые символы"])
        }
        
        return .success
    }
    
    func validateTemperature(_ temperature: Double) -> ValidationResult {
        if temperature < 0.0 {
            return .failure(["Температура не может быть отрицательной"])
        }
        
        if temperature > 2.0 {
            return .failure(["Температура не может быть больше 2.0"])
        }
        
        var warnings: [String] = []
        
        if temperature < 0.3 {
            warnings.append("Низкая температура: ответы будут детерминированными")
        } else if temperature > 1.5 {
            warnings.append("Высокая температура: ответы могут быть бессвязными")
        }
        
        if warnings.isEmpty {
            return .success
        } else {
            return ValidationResult(isValid: true, errors: [], warnings: warnings)
        }
    }
}

// MARK: - Connection Test

extension ValidateSettingsUseCase {
    
    /// Проверить подключение к серверу
    /// - Parameters:
    ///   - settings: Настройки подключения
    ///   - apiKey: API ключ
    /// - Returns: AsyncThrowingStream с результатом проверки
    func testConnection(
        settings: ChatSettings,
        apiKey: String
    ) async throws -> Bool {
        guard let url = URL(string: settings.serverURL) else {
            throw AppError.invalidURL(settings.serverURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10.0
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.network(.connection(NSError(domain: "Invalid response", code: -1)))
        }
        
        // Успешные коды: 200, 401 (API key может быть неверным, но сервер доступен)
        return httpResponse.statusCode == 200 || httpResponse.statusCode == 401
    }
}

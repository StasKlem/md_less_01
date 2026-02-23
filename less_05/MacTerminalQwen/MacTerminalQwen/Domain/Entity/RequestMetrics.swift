//
//  RequestMetrics.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

/// Entity метрик запроса к LLM API.
/// Используется для отображения статистики в UI.
struct RequestMetrics: Equatable {
    
    // MARK: - Token Statistics
    
    /// Количество токенов в запросе (prompt)
    var promptTokens: Int
    
    /// Количество токенов в ответе (completion)
    var completionTokens: Int
    
    /// Общее количество токенов
    var totalTokens: Int
    
    // MARK: - Performance Metrics
    
    /// Время выполнения запроса в секундах
    var duration: TimeInterval
    
    /// Скорость генерации (токенов в секунду)
    var tokensPerSecond: Double
    
    // MARK: - Model Information
    
    /// Название использованной модели
    var modelName: String?
    
    // MARK: - Initialization
    
    init(
        promptTokens: Int = 0,
        completionTokens: Int = 0,
        totalTokens: Int = 0,
        duration: TimeInterval = 0,
        tokensPerSecond: Double = 0,
        modelName: String? = nil
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.duration = duration
        self.tokensPerSecond = tokensPerSecond
        self.modelName = modelName
    }
    
    // MARK: - Computed Properties
    
    /// Проверить, есть ли данные о токенах
    var hasTokenData: Bool {
        totalTokens > 0
    }
    
    /// Проверить, есть ли данные о производительности
    var hasPerformanceData: Bool {
        duration > 0 && tokensPerSecond > 0
    }
    
    /// Форматированная строка скорости
    var formattedSpeed: String {
        String(format: "%.1f tok/s", tokensPerSecond)
    }
    
    /// Форматированная строка длительности
    var formattedDuration: String {
        if duration < 1.0 {
            return String(format: "%.0f ms", duration * 1000)
        } else {
            return String(format: "%.1f s", duration)
        }
    }
    
    // MARK: - Mutating Methods
    
    /// Обновить длительность и пересчитать скорость
    mutating func updateDuration(_ duration: TimeInterval) {
        self.duration = duration
        if duration > 0 && completionTokens > 0 {
            self.tokensPerSecond = Double(completionTokens) / duration
        }
    }
    
    /// Обновить данные о токенах
    mutating func updateTokens(prompt: Int?, completion: Int?, total: Int?) {
        if let prompt = prompt { self.promptTokens = prompt }
        if let completion = completion { self.completionTokens = completion }
        if let total = total { self.totalTokens = total }
    }
}

// MARK: - Usage Convenience

extension RequestMetrics {
    
    /// Создать метрики из данных использования токенов
    static func fromUsage(
        promptTokens: Int,
        completionTokens: Int,
        totalTokens: Int,
        modelName: String? = nil
    ) -> RequestMetrics {
        RequestMetrics(
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: totalTokens,
            modelName: modelName
        )
    }
    
    /// Пустые метрики
    static let empty = RequestMetrics()
}

// MARK: - Streaming Progress

/// Прогресс стриминга для обновления UI в реальном времени.
struct StreamingProgress: Equatable {
    
    /// Количество полученных чанков
    var chunkCount: Int
    
    /// Количество символов в ответе
    var characterCount: Int
    
    /// Время начала стриминга
    var startTime: Date?
    
    /// Время последнего обновления
    var lastUpdateTime: Date?
    
    /// Текущая скорость (токенов/сек)
    var currentSpeed: Double
    
    // MARK: - Initialization
    
    init(
        chunkCount: Int = 0,
        characterCount: Int = 0,
        startTime: Date? = nil,
        lastUpdateTime: Date? = nil,
        currentSpeed: Double = 0
    ) {
        self.chunkCount = chunkCount
        self.characterCount = characterCount
        self.startTime = startTime
        self.lastUpdateTime = lastUpdateTime
        self.currentSpeed = currentSpeed
    }
    
    // MARK: - Mutating Methods
    
    /// Обновить прогресс при получении нового чанка
    mutating func appendChunk(_ text: String) {
        chunkCount += 1
        characterCount += text.count
        lastUpdateTime = Date()
        
        if startTime == nil {
            startTime = lastUpdateTime
        }
        
        // Пересчитать скорость
        if let start = startTime,
           let last = lastUpdateTime,
           last.timeIntervalSince(start) > 0 {
            let elapsed = last.timeIntervalSince(start)
            currentSpeed = Double(chunkCount) / elapsed
        }
    }
    
    /// Сбросить прогресс
    mutating func reset() {
        self = StreamingProgress()
    }
    
    // MARK: - Computed Properties
    
    /// Общее время стриминга
    var elapsedTime: TimeInterval {
        guard let start = startTime, let last = lastUpdateTime else {
            return 0
        }
        return last.timeIntervalSince(start)
    }
    
    /// Форматированная скорость
    var formattedSpeed: String {
        String(format: "%.1f tok/s", currentSpeed)
    }
}

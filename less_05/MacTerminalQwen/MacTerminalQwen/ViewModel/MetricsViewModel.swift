//
//  MetricsViewModel.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation
import Combine

/// ViewModel для отображения метрик запроса.
@MainActor
final class MetricsViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Текущие метрики
    @Published private(set) var metrics: RequestMetrics = .empty
    
    /// Индикатор активного запроса
    @Published private(set) var isActive: Bool = false
    
    /// Прогресс стриминга
    @Published private(set) var streamingProgress: StreamingProgress = .init()
    
    /// История метрик (для статистики)
    @Published private(set) var history: [RequestMetrics] = []
    
    // MARK: - Computed Properties
    
    /// Форматированная скорость генерации
    var formattedSpeed: String {
        metrics.formattedSpeed
    }
    
    /// Форматированная длительность
    var formattedDuration: String {
        metrics.formattedDuration
    }
    
    /// Форматированное количество токенов
    var formattedTokens: String {
        if metrics.hasTokenData {
            return "\(metrics.totalTokens) tokens (prompt: \(metrics.promptTokens), completion: \(metrics.completionTokens))"
        } else {
            return "—"
        }
    }
    
    /// Название модели
    var formattedModel: String {
        metrics.modelName ?? "—"
    }
    
    // MARK: - Public Methods
    
    /// Обновить метрики
    func updateMetrics(_ metrics: RequestMetrics) {
        self.metrics = metrics
        isActive = true
    }
    
    /// Обновить прогресс стриминга
    func updateStreamingProgress(_ progress: StreamingProgress) {
        streamingProgress = progress
        
        // Обновить скорость в метриках
        if progress.elapsedTime > 0 {
            var newMetrics = metrics
            newMetrics.tokensPerSecond = progress.currentSpeed
            newMetrics.completionTokens = progress.chunkCount
            self.metrics = newMetrics
        }
    }
    
    /// Завершить запрос
    func finishRequest(metrics: RequestMetrics) {
        self.metrics = metrics
        isActive = false
        
        // Добавить в историю
        history.append(metrics)
        
        // Ограничить историю
        if history.count > 10 {
            history.removeFirst()
        }
    }
    
    /// Сбросить текущие метрики
    func reset() {
        metrics = .empty
        streamingProgress = .init()
        isActive = false
    }
    
    /// Очистить историю
    func clearHistory() {
        history.removeAll()
    }
}

// MARK: - Statistics

extension MetricsViewModel {
    
    /// Средняя скорость генерации
    var averageSpeed: Double {
        guard !history.isEmpty else { return 0 }
        let totalSpeed = history.reduce(0) { $0 + $1.tokensPerSecond }
        return totalSpeed / Double(history.count)
    }
    
    /// Среднее количество токенов
    var averageTokens: Int {
        guard !history.isEmpty else { return 0 }
        let totalTokens = history.reduce(0) { $0 + $1.totalTokens }
        return totalTokens / history.count
    }
    
    /// Форматированная средняя скорость
    var formattedAverageSpeed: String {
        String(format: "%.1f tok/s", averageSpeed)
    }
}

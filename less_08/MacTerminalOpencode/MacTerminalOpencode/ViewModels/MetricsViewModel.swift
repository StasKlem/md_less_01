//
//  MetricsViewModel.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

/// Represents metrics for a single request
struct RequestMetrics {
    var modelName: String
    var totalTokens: Int
    var promptTokens: Int
    var completionTokens: Int
    var tokensPerSecond: Double
    var requestDuration: TimeInterval
    var startTime: Date
    
    init(modelName: String = "") {
        self.modelName = modelName
        self.totalTokens = 0
        self.promptTokens = 0
        self.completionTokens = 0
        self.tokensPerSecond = 0
        self.requestDuration = 0
        self.startTime = Date()
    }
}

/// Callback types for MetricsViewModel state changes
enum MetricsViewModelEvent {
    case metricsUpdated(RequestMetrics)
    case reset
}

/// Manages and tracks request metrics
@MainActor
final class MetricsViewModel {
    
    private(set) var currentMetrics: RequestMetrics
    private var tokenCount: Int = 0
    private var startTime: Date?
    
    private let settingsViewModel: SettingsViewModel
    
    var onEvent: ((MetricsViewModelEvent) -> Void)?
    
    init(settingsViewModel: SettingsViewModel) {
        self.settingsViewModel = settingsViewModel
        self.currentMetrics = RequestMetrics(modelName: settingsViewModel.currentSettings.modelName)
    }
    
    /// Starts tracking a new request
    func startRequest() {
        tokenCount = 0
        startTime = Date()
        currentMetrics = RequestMetrics(modelName: settingsViewModel.currentSettings.modelName)
        print("[MetricsViewModel] Started request, model: \(currentMetrics.modelName)")
        onEvent?(.metricsUpdated(currentMetrics))
    }
    
    /// Records a new token received
    func recordToken() {
        tokenCount += 1
        updateMetrics()
    }
    
    /// Records multiple tokens at once
    func recordTokens(_ count: Int) {
        tokenCount += count
        print("[MetricsViewModel] Recorded \(count) tokens, total: \(tokenCount)")
        updateMetrics()
    }
    
    /// Completes the current request tracking
    func completeRequest(promptTokens: Int = 0, completionTokens: Int = 0) {
        currentMetrics.completionTokens = completionTokens > 0 ? completionTokens : tokenCount
        currentMetrics.promptTokens = promptTokens
        currentMetrics.totalTokens = currentMetrics.promptTokens + currentMetrics.completionTokens
        
        if let startTime = startTime {
            currentMetrics.requestDuration = Date().timeIntervalSince(startTime)
            
            if currentMetrics.requestDuration > 0 {
                currentMetrics.tokensPerSecond = Double(currentMetrics.completionTokens) / currentMetrics.requestDuration
            }
        }
        
        print("[MetricsViewModel] Request completed - tokens: \(currentMetrics.completionTokens), duration: \(String(format: "%.1f", currentMetrics.requestDuration))s, speed: \(String(format: "%.1f", currentMetrics.tokensPerSecond)) tok/s")
        onEvent?(.metricsUpdated(currentMetrics))
    }
    
    /// Resets all metrics
    func reset() {
        tokenCount = 0
        startTime = nil
        currentMetrics = RequestMetrics(modelName: settingsViewModel.currentSettings.modelName)
        onEvent?(.reset)
    }
    
    /// Updates the model name from settings
    func updateModelName() {
        currentMetrics.modelName = settingsViewModel.currentSettings.modelName
        onEvent?(.metricsUpdated(currentMetrics))
    }
    
    private func updateMetrics() {
        guard let startTime = startTime else { return }
        
        let duration = Date().timeIntervalSince(startTime)
        
        currentMetrics.completionTokens = tokenCount
        currentMetrics.requestDuration = duration
        
        if duration > 0 {
            currentMetrics.tokensPerSecond = Double(tokenCount) / duration
        }
        
        onEvent?(.metricsUpdated(currentMetrics))
    }
}

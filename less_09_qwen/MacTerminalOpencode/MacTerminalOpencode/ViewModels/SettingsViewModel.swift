//
//  SettingsViewModel.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

/// Callback types for SettingsViewModel state changes
enum SettingsViewModelEvent {
    case settingsChanged(LLMSettings)
    case apiKeyChanged(Bool)
    case validationError([SettingsValidationError])
    case saved
}

/// Manages application settings state
@MainActor
final class SettingsViewModel {
    
    private(set) var currentSettings: LLMSettings
    private(set) var hasAPIKey: Bool = false
    private(set) var availableModels: [String] = []
    
    private let settingsStorage: SettingsStorageProtocol
    private let keychainService: KeychainServiceProtocol
    private let fetchModelsUseCase: FetchModelsUseCaseProtocol
    
    var onEvent: ((SettingsViewModelEvent) -> Void)?
    
    init(
        settingsStorage: SettingsStorageProtocol,
        keychainService: KeychainServiceProtocol,
        fetchModelsUseCase: FetchModelsUseCaseProtocol
    ) {
        self.settingsStorage = settingsStorage
        self.keychainService = keychainService
        self.fetchModelsUseCase = fetchModelsUseCase
        
        self.currentSettings = settingsStorage.loadSettings()
        
        checkAPIKey()
    }
    
    /// Updates the server URL
    func updateServerURL(_ url: String) {
        currentSettings = LLMSettings(
            serverURL: url,
            modelName: currentSettings.modelName,
            temperature: currentSettings.temperature,
            maxTokens: currentSettings.maxTokens,
            enableStreaming: currentSettings.enableStreaming,
            systemPrompt: currentSettings.systemPrompt,
            saveContext: currentSettings.saveContext
        )
        onEvent?(.settingsChanged(currentSettings))
        saveSettingsSilently()
    }
    
    /// Updates the model name
    func updateModelName(_ name: String) {
        currentSettings = LLMSettings(
            serverURL: currentSettings.serverURL,
            modelName: name,
            temperature: currentSettings.temperature,
            maxTokens: currentSettings.maxTokens,
            enableStreaming: currentSettings.enableStreaming,
            systemPrompt: currentSettings.systemPrompt,
            saveContext: currentSettings.saveContext
        )
        onEvent?(.settingsChanged(currentSettings))
        saveSettingsSilently()
    }
    
    /// Updates the temperature value
    func updateTemperature(_ temperature: Double) {
        currentSettings = LLMSettings(
            serverURL: currentSettings.serverURL,
            modelName: currentSettings.modelName,
            temperature: temperature,
            maxTokens: currentSettings.maxTokens,
            enableStreaming: currentSettings.enableStreaming,
            systemPrompt: currentSettings.systemPrompt,
            saveContext: currentSettings.saveContext
        )
        onEvent?(.settingsChanged(currentSettings))
        saveSettingsSilently()
    }
    
    /// Updates the max tokens value
    func updateMaxTokens(_ maxTokens: Int) {
        currentSettings = LLMSettings(
            serverURL: currentSettings.serverURL,
            modelName: currentSettings.modelName,
            temperature: currentSettings.temperature,
            maxTokens: maxTokens,
            enableStreaming: currentSettings.enableStreaming,
            systemPrompt: currentSettings.systemPrompt,
            saveContext: currentSettings.saveContext
        )
        onEvent?(.settingsChanged(currentSettings))
        saveSettingsSilently()
    }
    
    /// Updates the streaming toggle
    func updateStreaming(_ enabled: Bool) {
        currentSettings = LLMSettings(
            serverURL: currentSettings.serverURL,
            modelName: currentSettings.modelName,
            temperature: currentSettings.temperature,
            maxTokens: currentSettings.maxTokens,
            enableStreaming: enabled,
            systemPrompt: currentSettings.systemPrompt,
            saveContext: currentSettings.saveContext
        )
        onEvent?(.settingsChanged(currentSettings))
        saveSettingsSilently()
    }
    
    /// Updates the system prompt
    func updateSystemPrompt(_ prompt: String) {
        currentSettings = LLMSettings(
            serverURL: currentSettings.serverURL,
            modelName: currentSettings.modelName,
            temperature: currentSettings.temperature,
            maxTokens: currentSettings.maxTokens,
            enableStreaming: currentSettings.enableStreaming,
            systemPrompt: prompt,
            saveContext: currentSettings.saveContext
        )
        onEvent?(.settingsChanged(currentSettings))
        saveSettingsSilently()
    }
    
    /// Updates the save context toggle
    func updateSaveContext(_ enabled: Bool) {
        currentSettings = LLMSettings(
            serverURL: currentSettings.serverURL,
            modelName: currentSettings.modelName,
            temperature: currentSettings.temperature,
            maxTokens: currentSettings.maxTokens,
            enableStreaming: currentSettings.enableStreaming,
            systemPrompt: currentSettings.systemPrompt,
            saveContext: enabled
        )
        onEvent?(.settingsChanged(currentSettings))
        saveSettingsSilently()
    }

    /// Updates the summarization strategy
    func updateSummarizationStrategy(_ strategy: SummarizationStrategy) {
        currentSettings = LLMSettings(
            serverURL: currentSettings.serverURL,
            modelName: currentSettings.modelName,
            temperature: currentSettings.temperature,
            maxTokens: currentSettings.maxTokens,
            enableStreaming: currentSettings.enableStreaming,
            systemPrompt: currentSettings.systemPrompt,
            saveContext: currentSettings.saveContext,
            summarizationStrategy: strategy,
            summarizationPrompt: currentSettings.summarizationPrompt
        )
        onEvent?(.settingsChanged(currentSettings))
        saveSettingsSilently()
    }

    /// Updates the summarization prompt
    func updateSummarizationPrompt(_ prompt: String) {
        currentSettings = LLMSettings(
            serverURL: currentSettings.serverURL,
            modelName: currentSettings.modelName,
            temperature: currentSettings.temperature,
            maxTokens: currentSettings.maxTokens,
            enableStreaming: currentSettings.enableStreaming,
            systemPrompt: currentSettings.systemPrompt,
            saveContext: currentSettings.saveContext,
            summarizationStrategy: currentSettings.summarizationStrategy,
            summarizationPrompt: prompt
        )
        onEvent?(.settingsChanged(currentSettings))
        saveSettingsSilently()
    }
    
    /// Saves the API key to secure storage
    func saveAPIKey(_ key: String) {
        do {
            if key.isEmpty {
                try keychainService.deleteAPIKey()
                hasAPIKey = false
            } else {
                try keychainService.saveAPIKey(key)
                hasAPIKey = true
            }
            onEvent?(.apiKeyChanged(hasAPIKey))
        } catch {
            onEvent?(.validationError([.emptyServerURL]))
        }
    }
    
    /// Saves all settings to persistent storage
    func saveSettings() {
        let errors = currentSettings.validate()
        
        guard errors.isEmpty else {
            onEvent?(.validationError(errors))
            return
        }
        
        settingsStorage.saveSettings(currentSettings)
        onEvent?(.saved)
    }
    
    /// Fetches available models from the server
    func fetchAvailableModels() {
        Task { [weak self] in
            guard let self else { return }
            
            do {
                let models = try await self.fetchModelsUseCase.execute(settings: self.currentSettings)
                self.availableModels = models
            } catch {
                print("Failed to fetch models: \(error)")
            }
        }
    }
    
    private func checkAPIKey() {
        do {
            hasAPIKey = try keychainService.loadAPIKey() != nil
            onEvent?(.apiKeyChanged(hasAPIKey))
        } catch {
            hasAPIKey = false
        }
    }
    
    /// Saves settings without triggering validation or events
    private func saveSettingsSilently() {
        settingsStorage.saveSettings(currentSettings)
    }
}

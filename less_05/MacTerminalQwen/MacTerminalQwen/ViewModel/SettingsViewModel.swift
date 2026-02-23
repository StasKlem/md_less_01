//
//  SettingsViewModel.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation
import Combine

/// ViewModel для управления настройками приложения.
@MainActor
final class SettingsViewModel: ObservableObject {

    // MARK: - Published Properties

    /// URL сервера
    @Published var serverURL: String = ""

    /// Эндпоинт чата
    @Published var chatEndpoint: String = "/chat/completions"

    /// Название модели
    @Published var modelName: String = ""

    /// Температура
    @Published var temperature: Double = 0.7

    /// Max tokens
    @Published var maxTokens: Int? = nil

    /// Top P
    @Published var topP: Double? = nil

    /// Включить стриминг
    @Published var streamEnabled: Bool = true

    /// Таймаут (секунды)
    @Published var timeoutInterval: Double = 30.0

    /// Системный промпт
    @Published var systemPrompt: String = ""

    /// API Key (вводится пользователем, не сохраняется в ViewModel)
    @Published var apiKeyInput: String = ""

    /// Индикатор сохранения API Key
    @Published private(set) var hasAPIKey: Bool = false

    /// Индикатор загрузки
    @Published private(set) var isLoading: Bool = false

    /// Текущая ошибка
    @Published private(set) var error: AppError?

    /// Предупреждения валидации
    @Published private(set) var validationWarnings: [String] = []

    /// Ошибки валидации
    @Published private(set) var validationErrors: [String] = []

    // MARK: - Dependencies

    private let settingsService: SettingsService
    private let validateSettingsUseCase: ValidateSettingsUseCaseProtocol

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        settingsService: SettingsService,
        validateSettingsUseCase: ValidateSettingsUseCaseProtocol
    ) {
        self.settingsService = settingsService
        self.validateSettingsUseCase = validateSettingsUseCase

        Task {
            await loadSettings()
        }
        setupBindings()
    }

    // MARK: - Public Methods

    /// Загрузить настройки из сервиса
    func loadSettings() async {
        let settings = await settingsService.getChatSettings()

        serverURL = settings.serverURL
        chatEndpoint = settings.chatEndpoint
        modelName = settings.modelName
        temperature = settings.temperature
        maxTokens = settings.maxTokens
        topP = settings.topP
        streamEnabled = settings.streamEnabled
        timeoutInterval = settings.timeoutInterval
        systemPrompt = settings.systemPrompt ?? ""

        let apiKey = (try? await settingsService.loadAPIKey()) ?? ""
        hasAPIKey = !apiKey.isEmpty
    }

    /// Сохранить настройки
    func saveSettings() async -> Bool {
        error = nil
        validationErrors = []
        validationWarnings = []

        let settings = buildSettings()

        // Валидация
        let result = validateSettingsUseCase.execute(settings: settings)
        validationErrors = result.errors
        validationWarnings = result.warnings

        guard result.isValid else {
            error = .validation(result.errors.joined(separator: ", "))
            return false
        }

        // Сохранение
        do {
            await settingsService.update(from: settings)
            try await settingsService.save()
            return true
        } catch {
            self.error = .unknown(error)
            return false
        }
    }

    /// Сохранить API Key
    func saveAPIKey() async -> Bool {
        error = nil

        let trimmedKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKey.isEmpty else {
            // Пустой ключ — удаляем
            do {
                try await settingsService.deleteAPIKey()
                hasAPIKey = false
                apiKeyInput = ""
                return true
            } catch {
                self.error = .fromSettingsError(error)
                return false
            }
        }

        // Сохранение ключа
        do {
            try await settingsService.saveAPIKey(trimmedKey)
            hasAPIKey = true
            apiKeyInput = "" // Очистить поле ввода
            return true
        } catch {
            self.error = .fromSettingsError(error)
            return false
        }
    }

    /// Удалить API Key
    func deleteAPIKey() {
        Task {
            do {
                try await settingsService.deleteAPIKey()
                hasAPIKey = false
                apiKeyInput = ""
            } catch {
                self.error = .fromSettingsError(error)
            }
        }
    }

    /// Сбросить настройки к значениям по умолчанию
    func resetToDefaults() {
        Task {
            await settingsService.resetToDefaults()
            await loadSettings()
        }
    }

    /// Протестировать подключение
    func testConnection() async -> Bool {
        isLoading = true
        error = nil

        let settings = buildSettings()

        do {
            let apiKey = (try? await settingsService.loadAPIKey()) ?? ""

            let validator = validateSettingsUseCase as? ValidateSettingsUseCase
            let isConnected = try await validator?.testConnection(
                settings: settings,
                apiKey: apiKey
            ) ?? false

            if !isConnected {
                error = .network(.connection(NSError(domain: "Connection test failed", code: -1)))
            }

            isLoading = false
            return isConnected
        } catch {
            self.error = error as? AppError ?? .unknown(error)
            isLoading = false
            return false
        }
    }

    // MARK: - Private Methods

    private func buildSettings() -> ChatSettings {
        ChatSettings(
            serverURL: serverURL,
            chatEndpoint: chatEndpoint,
            modelName: modelName,
            temperature: temperature,
            maxTokens: maxTokens,
            topP: topP,
            streamEnabled: streamEnabled,
            timeoutInterval: timeoutInterval,
            systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt
        )
    }

    private func setupBindings() {
        // Автоматическая валидация при изменении полей
        Publishers.CombineLatest4($serverURL, $modelName, $temperature, $timeoutInterval)
            .debounce(for: 0.3, scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.validateCurrentSettings()
                }
            }
            .store(in: &cancellables)
    }

    private func validateCurrentSettings() {
        let settings = buildSettings()
        let result = validateSettingsUseCase.execute(settings: settings)

        validationErrors = result.errors
        validationWarnings = result.warnings
    }
}

// MARK: - Computed Properties

extension SettingsViewModel {

    /// Проверить, валидны ли текущие настройки
    var isValid: Bool {
        validationErrors.isEmpty
    }
}

//
//  AppContainer.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

/// Контейнер зависимостей приложения.
/// Отвечает за создание и предоставление всех зависимостей.
final class AppContainer {

    // MARK: - Singleton

    static let shared = AppContainer()

    // MARK: - Services

    lazy var settingsService: SettingsService = {
        SettingsService()
    }()

    // MARK: - Data Layer

    lazy var networkManager: NetworkManagerProtocol = {
        NetworkManager(timeout: 60.0)
    }()

    lazy var chatRepository: ChatRepositoryProtocol = {
        ChatRepository(networkManager: networkManager)
    }()

    // MARK: - Domain Layer

    lazy var validateSettingsUseCase: ValidateSettingsUseCaseProtocol = {
        ValidateSettingsUseCase()
    }()

    lazy var sendMessageUseCase: SendMessageUseCaseProtocol = {
        SendMessageUseCase(repository: chatRepository)
    }()

    lazy var streamResponseUseCase: StreamResponseUseCaseProtocol = {
        StreamResponseUseCase(
            repository: chatRepository,
            settingsService: settingsService
        )
    }()

    // MARK: - ViewModel Layer

    func makeChatViewModel() -> ChatViewModel {
        ChatViewModel(
            streamResponseUseCase: streamResponseUseCase,
            settingsService: settingsService
        )
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(
            settingsService: settingsService,
            validateSettingsUseCase: validateSettingsUseCase
        )
    }

    func makeMetricsViewModel() -> MetricsViewModel {
        MetricsViewModel()
    }

    // MARK: - UI Layer

    func makeMainSplitViewController() -> MainSplitViewController {
        let splitVC = MainSplitViewController()
        return splitVC
    }

    func makeMainWindowController() -> MainWindowController {
        MainWindowController()
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Setup

    /// Инициализировать контейнер (загрузить настройки)
    func setup() {
        logInfo("AppContainer initialized")
    }
}

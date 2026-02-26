//
//  AppDelegate.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 22.02.2026.
//

import AppKit
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!
    private var mainSplitViewController: MainSplitViewController?

    private var chatSession: ChatSession!
    private var networkManager: NetworkManager!
    private var apiClient: LLMAPIClient!
    private var settingsStorage: SettingsStorage!
    private var keychainService: KeychainService!
    private var chatStorage: ChatStorage!
    private var conversationSummaryStorage: ConversationSummaryStorage!
    private var summarizationService: SummarizationService!

    private var sendMessageUseCase: SendMessageUseCase!
    private var fetchModelsUseCase: FetchModelsUseCase!

    private var settingsViewModel: SettingsViewModel!
    private var metricsViewModel: MetricsViewModel!
    private var chatViewModel: ChatViewModel!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupDependencies()
        setupMainWindow()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    private func setupDependencies() {
        chatSession = ChatSession()
        networkManager = NetworkManager(timeoutInterval: Constants.Network.defaultTimeout)
        apiClient = LLMAPIClient(networkManager: networkManager)
        settingsStorage = SettingsStorage()
        keychainService = KeychainService(service: Constants.Storage.keychainService)
        chatStorage = ChatStorage()
        conversationSummaryStorage = ConversationSummaryStorage()
        summarizationService = SummarizationService(apiClient: apiClient)

        Task {
            await chatSession.configureSummaryStorage(storage: conversationSummaryStorage)
        }

        sendMessageUseCase = SendMessageUseCase(
            apiClient: apiClient,
            keychainService: keychainService,
            chatSession: chatSession
        )

        fetchModelsUseCase = FetchModelsUseCase(
            apiClient: apiClient,
            keychainService: keychainService
        )

        settingsViewModel = SettingsViewModel(
            settingsStorage: settingsStorage,
            keychainService: keychainService,
            fetchModelsUseCase: fetchModelsUseCase
        )

        metricsViewModel = MetricsViewModel(settingsViewModel: settingsViewModel)

        chatViewModel = ChatViewModel(
            sendMessageUseCase: sendMessageUseCase,
            chatSession: chatSession,
            settingsViewModel: settingsViewModel,
            metricsViewModel: metricsViewModel,
            chatStorage: chatStorage,
            summarizationService: summarizationService
        )

        chatViewModel.setKeychainService(keychainService)
    }

    private func setupMainWindow() {
        mainSplitViewController = MainSplitViewController()

        mainSplitViewController?.configure(
            chatViewModel: chatViewModel,
            settingsViewModel: settingsViewModel,
            metricsViewModel: metricsViewModel
        )

        // Force view load
        _ = mainSplitViewController?.view

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "LLM Client"
        window.center()
        window.contentView = mainSplitViewController?.view
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        self.window = window

        NSApp.activate(ignoringOtherApps: true)
    }
}

////
////  AppDelegate.swift
////  MacTerminalOpencode
////
////  Created by Stas Klem on 22.02.2026.
////
//
import AppKit
import Cocoa
//
//@main
//class AppDelegate: NSObject, NSApplicationDelegate {
//
//    var window: NSWindow!
//    private var mainSplitViewController: MainSplitViewController?
//    
//    private var chatSession: ChatSession!
//    private var networkManager: NetworkManager!
//    private var apiClient: LLMAPIClient!
//    private var settingsStorage: SettingsStorage!
//    private var keychainService: KeychainService!
//    private var chatStorage: ChatStorage!
//    
//    private var sendMessageUseCase: SendMessageUseCase!
//    private var fetchModelsUseCase: FetchModelsUseCase!
//    
//    private var settingsViewModel: SettingsViewModel!
//    private var metricsViewModel: MetricsViewModel!
//    private var chatViewModel: ChatViewModel!
//    
//    func applicationDidFinishLaunching(_ aNotification: Notification) {
//        setupDependencies()
//        setupMainWindow()
//    }
//    
//    func applicationWillTerminate(_ aNotification: Notification) {
//    }
//    
//    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
//        return true
//    }
//    
//    private func setupDependencies() {
//        chatSession = ChatSession()
//        networkManager = NetworkManager(timeoutInterval: Constants.Network.defaultTimeout)
//        apiClient = LLMAPIClient(networkManager: networkManager)
//        settingsStorage = SettingsStorage()
//        keychainService = KeychainService(service: Constants.Storage.keychainService)
//        chatStorage = ChatStorage()
//        
//        sendMessageUseCase = SendMessageUseCase(
//            apiClient: apiClient,
//            keychainService: keychainService,
//            chatSession: chatSession
//        )
//        
//        fetchModelsUseCase = FetchModelsUseCase(
//            apiClient: apiClient,
//            keychainService: keychainService
//        )
//        
//        settingsViewModel = SettingsViewModel(
//            settingsStorage: settingsStorage,
//            keychainService: keychainService,
//            fetchModelsUseCase: fetchModelsUseCase
//        )
//        
//        metricsViewModel = MetricsViewModel(settingsViewModel: settingsViewModel)
//        
//        chatViewModel = ChatViewModel(
//            sendMessageUseCase: sendMessageUseCase,
//            chatSession: chatSession,
//            settingsViewModel: settingsViewModel,
//            metricsViewModel: metricsViewModel,
//            chatStorage: chatStorage
//        )
//    }
//    
//    private func setupMainWindow() {
//        mainSplitViewController = MainSplitViewController()
//
//        mainSplitViewController?.configure(
//            chatViewModel: chatViewModel,
//            settingsViewModel: settingsViewModel,
//            metricsViewModel: metricsViewModel
//        )
//
//        // Force view load
//        _ = mainSplitViewController?.view
//
//        let window = NSWindow(
//            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600),
//            styleMask: [.titled, .closable, .miniaturizable, .resizable],
//            backing: .buffered,
//            defer: false
//        )
//
//        window.title = "LLM Client"
//        window.center()
//        window.contentView = mainSplitViewController?.view
//        window.makeKeyAndOrderFront(nil)
//        window.orderFrontRegardless()
//
//        self.window = window
//
//        NSApp.activate(ignoringOtherApps: true)
//    }
//}


@main
class AppDelegate: NSObject, NSApplicationDelegate {

    // 2. ВАЖНО: Окно должно быть свойством класса (сильная ссылка).
    // Если сделать его локальной переменной в функции, окно исчезнет сразу после запуска.
    var window: NSWindow!
    
    override init() {
            super.init()
            print("🔵 AppDelegate: init() вызван")
        }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Создаем окно программно
        let windowRect = NSRect(x: 0, y: 0, width: 900, height: 600)
        
        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.center()
        window.title = "AppKit без Storyboard"
        window.makeKeyAndOrderFront(nil)
        
        // Создаем контент для окна
        let contentView = NSView()
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        
        // Пример добавления лейбла
        let label = NSTextField(labelWithString: "Привет! Это чистый AppKit с @main")
        label.frame = NSRect(x: 0, y: 0, width: 400, height: 40)
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        
        // Позиционируем лейбл по центру (упрощенно)
        label.frame.origin = NSPoint(
            x: (contentView.frame.width - label.frame.width) / 2,
            y: (contentView.frame.height - label.frame.height) / 2
        )
        
        contentView.addSubview(label)
        window.contentView = contentView
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}

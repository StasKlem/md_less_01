//
//  AppDelegate.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import AppKit

/// Делегат приложения для обработки событий жизненного цикла.
final class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var windowController: MainWindowController?
    private var appContainer: AppContainer!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[AppDelegate] applicationDidFinishLaunching called")
        
        // Инициализация контейнера зависимостей
        appContainer = AppContainer.shared
        appContainer.setup()
        
        // Устанавливаем политику активации (приложение с Dock и меню)
        NSApp.setActivationPolicy(.regular)
        
        // Создание главного окна
        windowController = MainWindowController()
        
        // Активация приложения
        NSApp.activate(ignoringOtherApps: true)
        windowController?.window.makeKeyAndOrderFront(nil)
        windowController?.window.orderFrontRegardless()
        
        print("[AppDelegate] Window shown: \(windowController?.window.isVisible ?? false)")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        print("[AppDelegate] Application will terminate")
        
        // Сохранение настроек перед завершением
        Task {
            let settingsService = AppContainer.shared.settingsService
            try? await settingsService.save()
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}

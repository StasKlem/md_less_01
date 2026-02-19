//
//  AppDelegate.swift
//  MacLlmTerminal
//
//  Created by Stas Klem on 19.02.2026.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var toolbarManager: ToolbarManager?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupMainWindow()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Cleanup if needed
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    private func setupMainWindow() {
        guard let window = NSApp.windows.first else { return }
        
        // Создаём SplitViewController
        let splitVC = SplitViewController()
        
        // Устанавливаем как contentViewController окна
        window.contentViewController = splitVC
        window.minSize = NSSize(width: 800, height: 600)
        window.setContentSize(NSSize(width: 1200, height: 700))
        window.center()
        
        // Создаём ToolbarManager после того как view загрузились
//        DispatchQueue.main.async { [weak self] in
//            guard let self = self,
//                  let chatVC = splitVC.chatViewController else { return }
//            self.toolbarManager = ToolbarManager(
//                splitViewController: splitVC,
//                chatViewController: chatVC
//            )
//            self.toolbarManager?.setupToolbar(for: window)
//        }
    }
}


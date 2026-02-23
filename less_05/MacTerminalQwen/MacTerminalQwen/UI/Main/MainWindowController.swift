//
//  MainWindowController.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import AppKit

/// Главное окно приложения.
final class MainWindowController: NSObject {

    let window: NSWindow

    override init() {
        guard let screen = NSScreen.main else {
            fatalError("No main screen available")
        }

        let windowWidth: CGFloat = 1200
        let windowHeight: CGFloat = 800
        let screenRect = screen.visibleFrame
        let x = (screenRect.width - windowWidth) / 2 + screenRect.origin.x
        let y = (screenRect.height - windowHeight) / 2 + screenRect.origin.y

        window = NSWindow(
            contentRect: NSRect(x: x, y: y, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "LLM Client"
        window.minSize = NSSize(width: 800, height: 0)  // Без ограничения по высоте
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.level = .normal

        super.init()
        
        window.delegate = self
        window.contentViewController = MainSplitViewController()
    }
    
    func show() {
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

extension MainWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
    }
}

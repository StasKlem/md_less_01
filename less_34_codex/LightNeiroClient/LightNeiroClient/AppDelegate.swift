//
//  AppDelegate.swift
//  LightNeiroClient
//
//  Created by Stas Klem on 28.02.2026.
//

import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum UI {
        static let defaultWindowWidth: CGFloat = 900
        static let defaultWindowHeight: CGFloat = 600
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let defaultFrame = NSRect(
            x: 0,
            y: 0,
            width: UI.defaultWindowWidth,
            height: UI.defaultWindowHeight
        )
        let window = NSWindow(
            contentRect: defaultFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.setFrame(defaultFrame, display: true)
        window.center()
        window.title = "LightNeiroClient"
        window.contentViewController = MainSplitViewController()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }
}

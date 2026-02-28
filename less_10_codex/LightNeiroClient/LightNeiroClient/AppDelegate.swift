//
//  AppDelegate.swift
//  LightNeiroClient
//
//  Created by Stas Klem on 28.02.2026.
//

import Cocoa


class AppDelegate: NSObject, NSApplicationDelegate {
    private enum UI {
        static let defaultWindowWidth: CGFloat = 900
        static let defaultWindowHeight: CGFloat = 600
    }

    private var window: NSWindow?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let viewController = ViewController()
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
        window.isRestorable = false
        window.setFrame(defaultFrame, display: true)
        window.center()
        window.setContentSize(NSSize(width: UI.defaultWindowWidth, height: UI.defaultWindowHeight))
        window.title = "LightNeiroClient"
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func applicationWillTerminate(_ aNotification: Notification) {
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return false
    }
}

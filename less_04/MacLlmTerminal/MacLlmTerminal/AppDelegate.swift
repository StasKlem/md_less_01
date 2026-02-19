//
//  AppDelegate.swift
//  MacLlmTerminal
//
//  Created by Stas Klem on 19.02.2026.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Setup menu bar extra items if needed
        setupMenuBar()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Cleanup if needed
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    private func setupMenuBar() {
        // Menu bar is configured in Main.storyboard
    }
}


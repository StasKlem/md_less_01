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
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window

        Task { @MainActor in
            let environment = await AppEnvironment.bootstrap()
            let chatViewModel = ChatViewModel(
                sessionID: environment.sessionID,
                branchID: environment.branchID,
                sendMessageUseCase: environment.sendMessageUseCase,
                fetchBranchesUseCase: environment.fetchBranchesUseCase,
                fetchMessagesUseCase: environment.fetchMessagesUseCase,
                cloneDialogToBranchUseCase: environment.cloneDialogToBranchUseCase,
                switchBranchUseCase: environment.switchBranchUseCase,
                createBranchUseCase: environment.createBranchUseCase,
                addBranchCreatedSystemMessageUseCase: environment.addBranchCreatedSystemMessageUseCase
            )
            let settingsViewModel = SettingsViewModel(
                sessionID: environment.sessionID,
                activeBranchID: environment.branchID,
                fetchSettingsUseCase: environment.fetchSettingsUseCase,
                applySettingsUseCase: environment.applySettingsUseCase,
                loadAPIKeyUseCase: environment.loadAPIKeyUseCase,
                saveAPIKeyUseCase: environment.saveAPIKeyUseCase
            )
            let sessionInfoViewModel = SessionInfoViewModel(
                sessionID: environment.sessionID,
                collectSessionMetricsUseCase: environment.collectSessionMetricsUseCase
            )
            let mainViewModel = MainViewModel(
                chatViewModel: chatViewModel,
                settingsViewModel: settingsViewModel,
                sessionInfoViewModel: sessionInfoViewModel
            )

            window.contentViewController = MainSplitViewController(viewModel: mainViewModel)
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return false
    }
}

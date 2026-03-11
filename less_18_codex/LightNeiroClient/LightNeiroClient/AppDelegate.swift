//
//  AppDelegate.swift
//  LightNeiroClient
//
//  Created by Stas Klem on 28.02.2026.
//

import Cocoa


class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private enum UI {
        static let defaultWindowWidth: CGFloat = 900
        static let defaultWindowHeight: CGFloat = 600
    }

    private enum Storage {
        static let mainWindowFrameKey = "mainWindowFrame"
    }

    private var window: NSWindow?
    private var startupFrame: NSRect?
    private var isWindowPersistenceEnabled = false

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
        window.delegate = self
        let savedFrame = loadSavedWindowFrame()
        startupFrame = savedFrame ?? defaultFrame
        if let startupFrame {
            window.setFrame(startupFrame, display: true)
        }
        if savedFrame == nil {
            window.center()
        }
        window.title = "LightNeiroClient"
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window

        Task { @MainActor in
            let environment = await AppEnvironment.bootstrap()
            let chatViewModel = ChatViewModel(
                session: environment.session,
                sendMessageUseCase: environment.sendMessageUseCase,
                fetchMessagesUseCase: environment.fetchMessagesUseCase,
                startVacationPlanningUseCase: environment.startVacationPlanningUseCase,
                handleVacationPlanningEventUseCase: environment.handleVacationPlanningEventUseCase,
                getVacationPlanningStatusUseCase: environment.getVacationPlanningStatusUseCase,
                fetchVacationPlannerMCPToolsUseCase: environment.fetchVacationPlannerMCPToolsUseCase,
                startMockTaskAgentUseCase: environment.startMockTaskAgentUseCase,
                handleMockTaskAgentEventUseCase: environment.handleMockTaskAgentEventUseCase,
                getMockTaskAgentStatusUseCase: environment.getMockTaskAgentStatusUseCase,
                startCounterTaskAgentUseCase: environment.startCounterTaskAgentUseCase,
                stopCounterTaskAgentUseCase: environment.stopCounterTaskAgentUseCase,
                configureCounterTaskAgentIntervalUseCase: environment.configureCounterTaskAgentIntervalUseCase,
                tickCounterTaskAgentUseCase: environment.tickCounterTaskAgentUseCase,
                getCounterTaskAgentStatusUseCase: environment.getCounterTaskAgentStatusUseCase,
                startHackerNewsTaskAgentUseCase: environment.startHackerNewsTaskAgentUseCase,
                stopHackerNewsTaskAgentUseCase: environment.stopHackerNewsTaskAgentUseCase,
                configureHackerNewsTaskAgentIntervalUseCase: environment.configureHackerNewsTaskAgentIntervalUseCase,
                tickHackerNewsTaskAgentUseCase: environment.tickHackerNewsTaskAgentUseCase,
                getHackerNewsTaskAgentStatusUseCase: environment.getHackerNewsTaskAgentStatusUseCase
            )
            let settingsViewModel = SettingsViewModel(
                session: environment.session,
                fetchSettingsUseCase: environment.fetchSettingsUseCase,
                applySettingsUseCase: environment.applySettingsUseCase,
                loadAPIKeyUseCase: environment.loadAPIKeyUseCase,
                saveAPIKeyUseCase: environment.saveAPIKeyUseCase
            )
            let sessionInfoViewModel = SessionInfoViewModel(
                session: environment.session,
                collectSessionMetricsUseCase: environment.collectSessionMetricsUseCase
            )
            let mainViewModel = MainViewModel(
                chatViewModel: chatViewModel,
                settingsViewModel: settingsViewModel,
                sessionInfoViewModel: sessionInfoViewModel
            )

            window.contentViewController = MainSplitViewController(viewModel: mainViewModel)
            if let startupFrame {
                window.setFrame(startupFrame, display: true)
            }
            isWindowPersistenceEnabled = true
            persistWindowFrame(of: window)
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        guard let window else { return }
        persistWindowFrame(of: window)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return false
    }

    func windowDidResize(_ notification: Notification) {
        guard isWindowPersistenceEnabled else { return }
        guard let window = notification.object as? NSWindow else { return }
        persistWindowFrame(of: window)
    }

    func windowDidMove(_ notification: Notification) {
        guard isWindowPersistenceEnabled else { return }
        guard let window = notification.object as? NSWindow else { return }
        persistWindowFrame(of: window)
    }

    private func loadSavedWindowFrame() -> NSRect? {
        guard let frameValue = UserDefaults.standard.string(forKey: Storage.mainWindowFrameKey) else {
            return nil
        }

        let frame = NSRectFromString(frameValue)
        guard !frame.equalTo(.zero) else {
            return nil
        }
        return frame
    }

    private func persistWindowFrame(of window: NSWindow) {
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: Storage.mainWindowFrameKey)
    }
}

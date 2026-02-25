//
//  MainSplitViewController.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 22.02.2026.
//

import AppKit

/// Main split view controller managing the three-panel layout
final class MainSplitViewController: NSSplitViewController {

    private var chatViewModel: ChatViewModel?
    private var settingsViewModel: SettingsViewModel?
    private var metricsViewModel: MetricsViewModel?

    private var chatPanel: ChatPanelViewController!
    private var settingsPanel: SettingsPanelViewController!
    private var metricsPanel: MetricsPanelViewController!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSplitView()
    }

    // MARK: - Configuration

    func configure(
        chatViewModel: ChatViewModel,
        settingsViewModel: SettingsViewModel,
        metricsViewModel: MetricsViewModel
    ) {
        self.chatViewModel = chatViewModel
        self.settingsViewModel = settingsViewModel
        self.metricsViewModel = metricsViewModel

        // Initialize panels first
        chatPanel = ChatPanelViewController()
        settingsPanel = SettingsPanelViewController()
        metricsPanel = MetricsPanelViewController()

        chatPanel.configure(with: chatViewModel)
        settingsPanel.configure(with: settingsViewModel)
        metricsPanel.configure(with: metricsViewModel)
    }

    // MARK: - Split View Setup

    private func setupSplitView() {
        guard chatPanel != nil, settingsPanel != nil, metricsPanel != nil else {
            return
        }

        splitView.dividerStyle = NSSplitView.DividerStyle.thin

        let chatSplitItem = NSSplitViewItem(viewController: chatPanel)
        chatSplitItem.collapseBehavior = .useConstraints
        chatSplitItem.minimumThickness = 400
        chatSplitItem.maximumThickness = 800
        chatSplitItem.isCollapsed = false

        let rightSplitViewController = NSSplitViewController()
        rightSplitViewController.splitView.dividerStyle = NSSplitView.DividerStyle.thin

        let settingsSplitItem = NSSplitViewItem(viewController: settingsPanel)
        settingsSplitItem.collapseBehavior = .useConstraints
        settingsSplitItem.minimumThickness = 200
        settingsSplitItem.maximumThickness = 400
        settingsSplitItem.isCollapsed = false

        let metricsSplitItem = NSSplitViewItem(viewController: metricsPanel)
        metricsSplitItem.collapseBehavior = .useConstraints
        metricsSplitItem.minimumThickness = 100
        metricsSplitItem.maximumThickness = 300
        metricsSplitItem.isCollapsed = false

        rightSplitViewController.addSplitViewItem(settingsSplitItem)
        rightSplitViewController.addSplitViewItem(metricsSplitItem)

        let rightSplitItem = NSSplitViewItem(viewController: rightSplitViewController)
        rightSplitItem.collapseBehavior = .useConstraints
        rightSplitItem.minimumThickness = 280
        rightSplitItem.maximumThickness = 600
        rightSplitItem.isCollapsed = false

        addSplitViewItem(chatSplitItem)
        addSplitViewItem(rightSplitItem)
    }
}

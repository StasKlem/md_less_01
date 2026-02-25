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
    
    private let chatPanel = ChatPanelViewController()
    private let settingsPanel = SettingsPanelViewController()
    private let metricsPanel = MetricsPanelViewController()
    
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
        
        chatPanel.configure(with: chatViewModel)
        settingsPanel.configure(with: settingsViewModel)
        metricsPanel.configure(with: metricsViewModel)
    }
    
    // MARK: - Split View Setup
    
    private func setupSplitView() {
        let chatSplitItem = NSSplitViewItem(sidebarWithViewController: chatPanel)
        chatSplitItem.minimumThickness = 400
        chatSplitItem.canCollapse = false
        
        let rightSplitViewController = NSSplitViewController()
        let settingsSplitItem = NSSplitViewItem(viewController: settingsPanel)
        settingsSplitItem.minimumThickness = 200
        settingsSplitItem.canCollapse = false
        
        let metricsSplitItem = NSSplitViewItem(viewController: metricsPanel)
        metricsSplitItem.minimumThickness = 100
        metricsSplitItem.canCollapse = false
        
        rightSplitViewController.addSplitViewItem(settingsSplitItem)
        rightSplitViewController.addSplitViewItem(metricsSplitItem)
        
        let rightSplitItem = NSSplitViewItem(viewController: rightSplitViewController)
        rightSplitItem.minimumThickness = 280
        rightSplitItem.maximumThickness = 600
        rightSplitItem.canCollapse = true
        
        addSplitViewItem(chatSplitItem)
        addSplitViewItem(rightSplitItem)
    }
}

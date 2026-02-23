//
//  MainSplitViewController.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import AppKit

/// Контроллер с разделённым видом для основного макета.
final class MainSplitViewController: NSSplitViewController {

    private(set) var chatViewController: ChatViewController!
    private(set) var settingsViewController: SettingsViewController!
    private(set) var metricsViewController: MetricsViewController!

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSplitView()
        setupViewControllers()
    }

    private func setupSplitView() {
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autosaveName = "MainSplitView"
    }

    private func setupViewControllers() {
        let chatViewModel = AppContainer.shared.makeChatViewModel()
        let metricsViewModel = AppContainer.shared.makeMetricsViewModel()
        let settingsService = AppContainer.shared.settingsService

        chatViewController = ChatViewController(viewModel: chatViewModel)
        settingsViewController = SettingsViewController(settingsService: settingsService)
        metricsViewController = MetricsViewController(viewModel: metricsViewModel)

        let rightSplitViewController = NSSplitViewController()
        rightSplitViewController.splitView.isVertical = false
        rightSplitViewController.splitView.dividerStyle = .thin

        let settingsItem = NSSplitViewItem(viewController: settingsViewController)
        settingsItem.minimumThickness = 280
        settingsItem.collapseBehavior = .useConstraints

        let metricsItem = NSSplitViewItem(viewController: metricsViewController)
        metricsItem.minimumThickness = 150
        metricsItem.collapseBehavior = .useConstraints

        rightSplitViewController.addSplitViewItem(settingsItem)
        rightSplitViewController.addSplitViewItem(metricsItem)

        let chatItem = NSSplitViewItem(viewController: chatViewController)
        chatItem.minimumThickness = 400
        chatItem.collapseBehavior = .useConstraints

        let rightItem = NSSplitViewItem(viewController: rightSplitViewController)
        rightItem.minimumThickness = 480
        rightItem.collapseBehavior = .useConstraints

        addSplitViewItem(chatItem)
        addSplitViewItem(rightItem)
    }
}

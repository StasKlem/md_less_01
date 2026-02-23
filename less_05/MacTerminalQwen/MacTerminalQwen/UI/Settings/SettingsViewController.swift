//
//  SettingsViewController.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import AppKit

/// Контроллер для управления видом настроек.
final class SettingsViewController: NSViewController {
    
    // MARK: - Properties
    
    private let formService: SettingsFormService
    private var formView: SettingsFormView!
    
    // MARK: - Initialization
    
    init(settingsService: SettingsService) {
        self.formService = SettingsFormService(settingsService: settingsService)
        super.init(nibName: nil, bundle: nil)
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func loadView() {
        view = NSView()
        view.frame = NSRect(x: 0, y: 0, width: 350, height: 600)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupFormView()
    }
    
    // MARK: - Setup
    
    private func setupFormView() {
        formView = SettingsFormView(service: formService)
        view.addSubview(formView)
        formView.fillSuperview()
        
        formView.onTestConnection = { [weak self] in
            Task { @MainActor in
                await self?.testConnection()
            }
        }
    }
    
    // MARK: - Actions
    
    private func testConnection() async {
        formView.setLoading(true)
        
        // Тест подключения будет реализован отдельно
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        formView.setLoading(false)
    }
}

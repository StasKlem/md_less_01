//
//  SettingsPanelViewController.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 22.02.2026.
//

import AppKit

/// Settings panel for configuring LLM connection and parameters
final class SettingsPanelViewController: NSViewController {
    
    private let serverURLField = NSTextField()
    private let modelPopUpButton = NSPopUpButton()
    private let temperatureSlider = NSSlider()
    private let temperatureLabel = NSTextField(labelWithString: "0.7")
    private let maxTokensField = NSTextField()
    private let streamingToggle = NSButton(checkboxWithTitle: "Enable Streaming", target: nil, action: nil)
    private let saveContextToggle = NSButton(checkboxWithTitle: "Сохранять контекст", target: nil, action: nil)
    private let systemPromptField = NSTextField()
    private let apiKeyField = NSSecureTextField()
    private let autoSaveLabel = NSTextField(labelWithString: "Settings are saved automatically")
    
    private var viewModel: SettingsViewModel?
    
    private let stackView = NSStackView()
    
    // MARK: - Lifecycle
    
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 500))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    // MARK: - Configuration
    
    func configure(with viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        
        populateFields()
        
        viewModel.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleViewModelEvent(event)
            }
        }
    }
    
    private func populateFields() {
        guard let viewModel else { return }
        
        serverURLField.stringValue = viewModel.currentSettings.serverURL
        selectModel(viewModel.currentSettings.modelName)
        temperatureSlider.doubleValue = viewModel.currentSettings.temperature
        temperatureLabel.stringValue = String(format: "%.1f", viewModel.currentSettings.temperature)
        maxTokensField.stringValue = String(viewModel.currentSettings.maxTokens)
        streamingToggle.state = viewModel.currentSettings.enableStreaming ? .on : .off
        saveContextToggle.state = viewModel.currentSettings.saveContext ? .on : .off
        systemPromptField.stringValue = viewModel.currentSettings.systemPrompt
    }
    
    private func selectModel(_ modelId: String) {
        let models = Constants.Models.predefined
        for (index, model) in models.enumerated() {
            if model.id == modelId {
                modelPopUpButton.selectItem(at: index)
                return
            }
        }
        modelPopUpButton.selectItem(at: 0)
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        view.wantsLayer = true
        
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.spacing = 12
        stackView.alignment = .leading
        view.addSubview(stackView)
        
        addServerURLSection()
        addAPIKeySection()
        addModelNameSection()
        addTemperatureSection()
        addMaxTokensSection()
        addStreamingSection()
        addSaveContextSection()
        addSystemPromptSection()
        addButtons()
        
        setupConstraints()
    }
    
    private func addServerURLSection() {
        let label = NSTextField(labelWithString: "Server URL:")
        serverURLField.placeholderString = "http://localhost:11434/v1"
        serverURLField.delegate = self
        
        stackView.addArrangedSubview(label)
        stackView.addArrangedSubview(serverURLField)
    }
    
    private func addAPIKeySection() {
        let label = NSTextField(labelWithString: "API Key:")
        apiKeyField.placeholderString = "Enter your API key"
        apiKeyField.delegate = self
        
        stackView.addArrangedSubview(label)
        stackView.addArrangedSubview(apiKeyField)
    }
    
    private func addModelNameSection() {
        let label = NSTextField(labelWithString: "Model:")
        
        modelPopUpButton.translatesAutoresizingMaskIntoConstraints = false
        modelPopUpButton.target = self
        modelPopUpButton.action = #selector(modelChanged)
        
        let menu = NSMenu()
        for model in Constants.Models.predefined {
            let item = NSMenuItem(title: model.displayName, action: nil, keyEquivalent: "")
            item.representedObject = model.id
            menu.addItem(item)
        }
        modelPopUpButton.menu = menu
        
        stackView.addArrangedSubview(label)
        stackView.addArrangedSubview(modelPopUpButton)
    }
    
    private func addTemperatureSection() {
        let label = NSTextField(labelWithString: "Temperature:")
        
        temperatureSlider.minValue = 0
        temperatureSlider.maxValue = 2
        temperatureSlider.doubleValue = 0.7
        temperatureSlider.target = self
        temperatureSlider.action = #selector(temperatureChanged)
        
        let tempRow = NSStackView()
        tempRow.orientation = .horizontal
        tempRow.spacing = 8
        tempRow.addArrangedSubview(temperatureSlider)
        tempRow.addArrangedSubview(temperatureLabel)
        
        stackView.addArrangedSubview(label)
        stackView.addArrangedSubview(tempRow)
    }
    
    private func addMaxTokensSection() {
        let label = NSTextField(labelWithString: "Max Tokens:")
        maxTokensField.placeholderString = "2048"
        maxTokensField.delegate = self
        
        stackView.addArrangedSubview(label)
        stackView.addArrangedSubview(maxTokensField)
    }
    
    private func addStreamingSection() {
        streamingToggle.target = self
        streamingToggle.action = #selector(streamingChanged)
        stackView.addArrangedSubview(streamingToggle)
    }
    
    private func addSaveContextSection() {
        saveContextToggle.target = self
        saveContextToggle.action = #selector(saveContextChanged)
        stackView.addArrangedSubview(saveContextToggle)
    }
    
    private func addSystemPromptSection() {
        let label = NSTextField(labelWithString: "System Prompt:")
        systemPromptField.placeholderString = "You are a helpful assistant."
        systemPromptField.delegate = self
        
        stackView.addArrangedSubview(label)
        stackView.addArrangedSubview(systemPromptField)
    }
    
    private func addButtons() {
        autoSaveLabel.font = NSFont.systemFont(ofSize: 11)
        autoSaveLabel.textColor = NSColor.secondaryLabelColor
        stackView.addArrangedSubview(autoSaveLabel)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            serverURLField.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            apiKeyField.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            modelPopUpButton.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            temperatureSlider.widthAnchor.constraint(equalToConstant: 180),
            maxTokensField.widthAnchor.constraint(equalToConstant: 100),
            systemPromptField.widthAnchor.constraint(equalTo: stackView.widthAnchor)
        ])
    }
    
    // MARK: - Actions
    
    @objc private func modelChanged() {
        guard let selectedItem = modelPopUpButton.selectedItem,
              let modelId = selectedItem.representedObject as? String else { return }
        viewModel?.updateModelName(modelId)
    }
    
    @objc private func temperatureChanged() {
        let value = temperatureSlider.doubleValue
        temperatureLabel.stringValue = String(format: "%.1f", value)
        viewModel?.updateTemperature(value)
    }
    
    @objc private func streamingChanged() {
        viewModel?.updateStreaming(streamingToggle.state == .on)
    }
    
    @objc private func saveContextChanged() {
        viewModel?.updateSaveContext(saveContextToggle.state == .on)
    }
    
    // MARK: - ViewModel Events
    
    private func handleViewModelEvent(_ event: SettingsViewModelEvent) {
        switch event {
        case .settingsChanged:
            break
        case .apiKeyChanged:
            break
        case .validationError(let errors):
            showValidationErrors(errors)
        case .saved:
            break
        }
    }
    
    private func showValidationErrors(_ errors: [SettingsValidationError]) {
        let message = errors.map { $0.errorDescription ?? "Unknown error" }.joined(separator: "\n")
        
        let alert = NSAlert()
        alert.messageText = "Validation Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: view.window!)
    }
}

// MARK: - NSTextFieldDelegate

extension SettingsPanelViewController: NSTextFieldDelegate {
    
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else { return }
        
        if textField == serverURLField {
            viewModel?.updateServerURL(serverURLField.stringValue)
        } else if textField == apiKeyField {
            viewModel?.saveAPIKey(apiKeyField.stringValue)
        } else if textField == maxTokensField {
            if let tokens = Int(maxTokensField.stringValue) {
                viewModel?.updateMaxTokens(tokens)
            }
        } else if textField == systemPromptField {
            viewModel?.updateSystemPrompt(systemPromptField.stringValue)
        }
    }
}

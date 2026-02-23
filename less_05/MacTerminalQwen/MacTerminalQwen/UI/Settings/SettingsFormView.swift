//
//  SettingsFormView.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import AppKit
import Combine

/// Форма настроек подключения к LLM API.
final class SettingsFormView: NSView {
    
    // MARK: - Properties
    
    private let service: SettingsFormService
    
    // Text Fields
    private let serverURLField = NSTextField()
    private let chatEndpointField = NSTextField()
    private let modelNameField = NSTextField()
    private let apiKeyField = NSSecureTextField()
    private let systemPromptField = NSTextView()
    
    // Numeric Fields
    private let temperatureField = NSTextField()
    private let maxTokensField = NSTextField()
    private let topPField = NSTextField()
    private let timeoutField = NSTextField()
    
    // Checkboxes
    private let streamEnabledButton = NSButton(checkboxWithTitle: "Включить потоковый режим (SSE)", target: nil, action: nil)
    
    // Buttons
    private let saveButton = NSButton()
    private let resetButton = NSButton()
    private let testConnectionButton = NSButton()
    
    // Labels
    private let validationLabel = NSTextField(labelWithString: "")
    
    // Scroll View for System Prompt
    private let systemPromptScrollView = NSScrollView()
    
    // MARK: - Callbacks
    
    var onSave: (() -> Void)?
    var onReset: (() -> Void)?
    var onTestConnection: (() -> Void)?
    
    // MARK: - Initialization

    init(service: SettingsFormService) {
        self.service = service
        super.init(frame: NSRect.zero)
        setupForm()
        setupLayout()
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    
    private func setupForm() {
        // Server URL
        setupTextField(serverURLField, placeholder: "https://api.openai.com/v1")
        
        // Chat Endpoint
        setupTextField(chatEndpointField, placeholder: "/chat/completions")
        
        // Model Name
        setupTextField(modelNameField, placeholder: "gpt-3.5-turbo")
        
        // API Key
        setupSecureTextField(apiKeyField, placeholder: "sk-...")
        
        // Temperature
        setupTextField(temperatureField, placeholder: "0.7")
        
        // Max Tokens
        setupTextField(maxTokensField, placeholder: "Optional")
        
        // Top P
        setupTextField(topPField, placeholder: "Optional")
        
        // Timeout
        setupTextField(timeoutField, placeholder: "30")
        
        // System Prompt
        setupSystemPromptView()
        
        // Stream Enabled
        streamEnabledButton.target = self
        
        // Save Button
        saveButton.title = "Сохранить"
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "s"
        saveButton.target = self
        saveButton.action = #selector(saveTapped)
        
        // Reset Button
        resetButton.title = "Сбросить"
        resetButton.bezelStyle = .rounded
        resetButton.target = self
        resetButton.action = #selector(resetTapped)
        
        // Test Connection Button
        testConnectionButton.title = "Проверить подключение"
        testConnectionButton.bezelStyle = .rounded
        testConnectionButton.target = self
        testConnectionButton.action = #selector(testConnectionTapped)
        
        // Validation Label
        validationLabel.font = NSFont.systemFont(ofSize: 11)
        validationLabel.textColor = .systemRed
        validationLabel.lineBreakMode = .byWordWrapping
        validationLabel.maximumNumberOfLines = 3
        
        // Заполнить поля из сервиса
        updateUI()
    }
    
    private func setupLayout() {
        let margin: CGFloat = 12
        let fieldHeight: CGFloat = 24
        let spacing: CGFloat = 8
        
        // Создаём labels
        let serverURLLabel = createLabel("Server URL:")
        let endpointLabel = createLabel("Chat Endpoint:")
        let modelLabel = createLabel("Model Name:")
        let apiKeyLabel = createLabel("API Key:")
        let temperatureLabel = createLabel("Temperature:")
        let maxTokensLabel = createLabel("Max Tokens:")
        let topPLabel = createLabel("Top P:")
        let timeoutLabel = createLabel("Timeout (sec):")
        let systemPromptLabel = createLabel("System Prompt:")
        
        // Добавляем все элементы
        [serverURLLabel, serverURLField,
         endpointLabel, chatEndpointField,
         modelLabel, modelNameField,
         apiKeyLabel, apiKeyField,
         temperatureLabel, temperatureField,
         maxTokensLabel, maxTokensField,
         topPLabel, topPField,
         timeoutLabel, timeoutField,
         systemPromptLabel, systemPromptScrollView,
         streamEnabledButton,
         validationLabel,
         saveButton, resetButton, testConnectionButton].forEach {
            addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        
        // Активируем ограничения
        NSLayoutConstraint.activate([
            // Server URL
            serverURLLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            serverURLLabel.topAnchor.constraint(equalTo: topAnchor, constant: margin),
            serverURLLabel.widthAnchor.constraint(equalToConstant: 120),
            
            serverURLField.leadingAnchor.constraint(equalTo: serverURLLabel.trailingAnchor, constant: spacing),
            serverURLField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            serverURLField.topAnchor.constraint(equalTo: topAnchor, constant: margin),
            serverURLField.heightAnchor.constraint(equalToConstant: fieldHeight),
            
            // Chat Endpoint
            endpointLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            endpointLabel.topAnchor.constraint(equalTo: serverURLField.bottomAnchor, constant: spacing),
            endpointLabel.widthAnchor.constraint(equalToConstant: 120),
            
            chatEndpointField.leadingAnchor.constraint(equalTo: endpointLabel.trailingAnchor, constant: spacing),
            chatEndpointField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            chatEndpointField.topAnchor.constraint(equalTo: serverURLField.bottomAnchor, constant: spacing),
            chatEndpointField.heightAnchor.constraint(equalToConstant: fieldHeight),
            
            // Model Name
            modelLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            modelLabel.topAnchor.constraint(equalTo: chatEndpointField.bottomAnchor, constant: spacing),
            modelLabel.widthAnchor.constraint(equalToConstant: 120),
            
            modelNameField.leadingAnchor.constraint(equalTo: modelLabel.trailingAnchor, constant: spacing),
            modelNameField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            modelNameField.topAnchor.constraint(equalTo: chatEndpointField.bottomAnchor, constant: spacing),
            modelNameField.heightAnchor.constraint(equalToConstant: fieldHeight),
            
            // API Key
            apiKeyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            apiKeyLabel.topAnchor.constraint(equalTo: modelNameField.bottomAnchor, constant: spacing),
            apiKeyLabel.widthAnchor.constraint(equalToConstant: 120),
            
            apiKeyField.leadingAnchor.constraint(equalTo: apiKeyLabel.trailingAnchor, constant: spacing),
            apiKeyField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            apiKeyField.topAnchor.constraint(equalTo: modelNameField.bottomAnchor, constant: spacing),
            apiKeyField.heightAnchor.constraint(equalToConstant: fieldHeight),
            
            // Temperature
            temperatureLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            temperatureLabel.topAnchor.constraint(equalTo: apiKeyField.bottomAnchor, constant: spacing),
            temperatureLabel.widthAnchor.constraint(equalToConstant: 120),
            
            temperatureField.leadingAnchor.constraint(equalTo: temperatureLabel.trailingAnchor, constant: spacing),
            temperatureField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            temperatureField.topAnchor.constraint(equalTo: apiKeyField.bottomAnchor, constant: spacing),
            temperatureField.heightAnchor.constraint(equalToConstant: fieldHeight),
            
            // Max Tokens
            maxTokensLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            maxTokensLabel.topAnchor.constraint(equalTo: temperatureField.bottomAnchor, constant: spacing),
            maxTokensLabel.widthAnchor.constraint(equalToConstant: 120),
            
            maxTokensField.leadingAnchor.constraint(equalTo: maxTokensLabel.trailingAnchor, constant: spacing),
            maxTokensField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            maxTokensField.topAnchor.constraint(equalTo: temperatureField.bottomAnchor, constant: spacing),
            maxTokensField.heightAnchor.constraint(equalToConstant: fieldHeight),
            
            // Top P
            topPLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            topPLabel.topAnchor.constraint(equalTo: maxTokensField.bottomAnchor, constant: spacing),
            topPLabel.widthAnchor.constraint(equalToConstant: 120),
            
            topPField.leadingAnchor.constraint(equalTo: topPLabel.trailingAnchor, constant: spacing),
            topPField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            topPField.topAnchor.constraint(equalTo: maxTokensField.bottomAnchor, constant: spacing),
            topPField.heightAnchor.constraint(equalToConstant: fieldHeight),
            
            // Timeout
            timeoutLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            timeoutLabel.topAnchor.constraint(equalTo: topPField.bottomAnchor, constant: spacing),
            timeoutLabel.widthAnchor.constraint(equalToConstant: 120),
            
            timeoutField.leadingAnchor.constraint(equalTo: timeoutLabel.trailingAnchor, constant: spacing),
            timeoutField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            timeoutField.topAnchor.constraint(equalTo: topPField.bottomAnchor, constant: spacing),
            timeoutField.heightAnchor.constraint(equalToConstant: fieldHeight),
            
            // System Prompt
            systemPromptLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            systemPromptLabel.topAnchor.constraint(equalTo: timeoutField.bottomAnchor, constant: spacing),
            
            systemPromptScrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            systemPromptScrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            systemPromptScrollView.topAnchor.constraint(equalTo: systemPromptLabel.bottomAnchor, constant: 4),
            systemPromptScrollView.heightAnchor.constraint(equalToConstant: 60),
            
            // Stream Enabled
            streamEnabledButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            streamEnabledButton.topAnchor.constraint(equalTo: systemPromptScrollView.bottomAnchor, constant: spacing),
            
            // Validation Label
            validationLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            validationLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            validationLabel.topAnchor.constraint(equalTo: streamEnabledButton.bottomAnchor, constant: spacing),
            
            // Buttons
            saveButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            saveButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -margin),
            saveButton.widthAnchor.constraint(equalToConstant: 100),
            
            resetButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -spacing),
            resetButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -margin),
            resetButton.widthAnchor.constraint(equalToConstant: 100),
            
            testConnectionButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            testConnectionButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -margin),
            testConnectionButton.widthAnchor.constraint(equalToConstant: 140)
        ])
    }
    
    // MARK: - UI Update

    private func updateUI() {
        serverURLField.stringValue = service.serverURL
        chatEndpointField.stringValue = service.chatEndpoint
        modelNameField.stringValue = service.modelName
        temperatureField.doubleValue = service.temperature
        maxTokensField.stringValue = service.maxTokens
        topPField.stringValue = service.topP
        streamEnabledButton.state = service.streamEnabled ? .on : .off
        timeoutField.doubleValue = service.timeoutInterval
        systemPromptField.string = service.systemPrompt
        apiKeyField.stringValue = service.hasAPIKey ? "••••••" : ""
    }

    // MARK: - Actions

    @objc private func saveTapped() {
        // Синхронизация UI с сервисом
        service.serverURL = serverURLField.stringValue
        service.chatEndpoint = chatEndpointField.stringValue
        service.modelName = modelNameField.stringValue
        service.temperature = temperatureField.doubleValue
        service.maxTokens = maxTokensField.stringValue
        service.topP = topPField.stringValue
        service.streamEnabled = streamEnabledButton.state == .on
        service.timeoutInterval = timeoutField.doubleValue
        service.systemPrompt = systemPromptField.string
        
        Task { @MainActor in
            let errors = service.validate()
            
            if errors.isEmpty {
                do {
                    try await service.saveToSettingsService()
                    if !apiKeyField.stringValue.isEmpty && apiKeyField.stringValue != "••••••" {
                        service.apiKeyInput = apiKeyField.stringValue
                        try await service.saveAPIKey()
                    }
                    showValidationMessage("Настройки сохранены", isError: false)
                } catch {
                    showValidationMessage(error.localizedDescription, isError: true)
                }
            } else {
                showValidationMessage(errors.joined(separator: "\n"), isError: true)
            }
        }
    }
    
    @objc private func resetTapped() {
        let alert = NSAlert()
        alert.messageText = "Сбросить настройки?"
        alert.informativeText = "Все настройки будут возвращены к значениям по умолчанию."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Сбросить")
        alert.addButton(withTitle: "Отмена")
        
        alert.beginSheetModal(for: window!) { [weak self] response in
            if response == .alertFirstButtonReturn {
                self?.service.resetToDefaults()
            }
        }
    }
    
    @objc private func testConnectionTapped() {
        onTestConnection?()
    }
    
    // MARK: - Helpers
    
    private func setupTextField(_ textField: NSTextField, placeholder: String) {
        textField.placeholderString = placeholder
        textField.bezelStyle = .roundedBezel
        setupContextMenu(for: textField)  // Добавляем контекстное меню
    }

    private func setupSecureTextField(_ textField: NSSecureTextField, placeholder: String) {
        textField.placeholderString = placeholder
        textField.bezelStyle = .roundedBezel
        textField.isEditable = true
        textField.isSelectable = true
        setupContextMenu(for: textField)  // Добавляем контекстное меню
    }
    
    private func setupSystemPromptView() {
        systemPromptField.isEditable = true
        systemPromptField.isSelectable = true
        systemPromptField.drawsBackground = true
        systemPromptField.font = NSFont.systemFont(ofSize: 13)
        systemPromptField.textContainer?.lineFragmentPadding = 4
        
        systemPromptScrollView.hasVerticalScroller = true
        systemPromptScrollView.autohidesScrollers = true
        systemPromptScrollView.documentView = systemPromptField
        systemPromptScrollView.translatesAutoresizingMaskIntoConstraints = false
    }
    
    private func createLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
    
    private func showValidationMessage(_ message: String, isError: Bool) {
        validationLabel.stringValue = message
        validationLabel.isHidden = message.isEmpty
        validationLabel.textColor = isError ? .systemRed : .systemOrange
    }
    
    func updateValidationLabels(errors: [String], warnings: [String]) {
        var messages: [String] = []
        messages.append(contentsOf: errors.map { "❌ \($0)" })
        messages.append(contentsOf: warnings.map { "⚠️ \($0)" })
        
        validationLabel.stringValue = messages.joined(separator: "\n")
        validationLabel.isHidden = messages.isEmpty
        validationLabel.textColor = errors.isEmpty ? .systemOrange : .systemRed
    }
    
    func setLoading(_ isLoading: Bool) {
        testConnectionButton.isEnabled = !isLoading
        saveButton.isEnabled = !isLoading
        
        if isLoading {
            testConnectionButton.title = "Проверка..."
        } else {
            testConnectionButton.title = "Проверить подключение"
        }
    }
}

// MARK: - Context Menu

extension SettingsFormView {

    private func setupContextMenu(for textField: NSTextField) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Вырезать", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        menu.addItem(NSMenuItem(title: "Копировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Выделить всё", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        textField.menu = menu
    }
}

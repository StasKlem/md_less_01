import Cocoa

// MARK: - Main Chat View Controller

final class ViewController: NSViewController {
    
    // MARK: - Properties
    
    private let llmService = LLMService()
    private var settings = ChatSettings.default
    private var messages: [Message] = []
    private var chatState: ChatState = .idle {
        didSet {
            updateStateUI()
        }
    }
    
    // MARK: - UI Elements - Settings Panel
    
    private lazy var settingsStackView: NSStackView = {
        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private lazy var modelTextField: NSTextField = {
        let textField = NSTextField()
        textField.placeholderString = "deepseek/deepseek-v3.2"
        textField.stringValue = ChatSettings.default.model
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private lazy var apiKeyTextField: NSSecureTextField = {
        let textField = NSSecureTextField()
        textField.placeholderString = "API Key"
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private lazy var temperatureSlider: NSSlider = {
        let slider = NSSlider()
        slider.minValue = 0
        slider.maxValue = 2
        slider.doubleValue = ChatSettings.default.temperature
        slider.translatesAutoresizingMaskIntoConstraints = false
        return slider
    }()
    
    private lazy var temperatureLabel: NSTextField = {
        let label = NSTextField(labelWithString: "T: 0.70")
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var topPSlider: NSSlider = {
        let slider = NSSlider()
        slider.minValue = 0
        slider.maxValue = 1
        slider.doubleValue = ChatSettings.default.topP
        slider.translatesAutoresizingMaskIntoConstraints = false
        return slider
    }()
    
    private lazy var topPLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Top-P: 0.90")
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var streamSwitch: NSSwitch = {
        let switchControl = NSSwitch()
        switchControl.state = ChatSettings.default.stream ? .on : .off
        switchControl.translatesAutoresizingMaskIntoConstraints = false
        return switchControl
    }()
    
    private lazy var streamLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Stream")
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var systemPromptTextField: NSTextField = {
        let textField = NSTextField()
        textField.placeholderString = "System prompt"
        textField.stringValue = ChatSettings.default.systemPrompt
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private lazy var clearChatButton: NSButton = {
        let button = NSButton()
        button.title = "🗑️ Очистить"
        button.bezelStyle = .rounded
        button.target = self
        button.action = #selector(clearChatTapped)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - UI Elements - Chat Area
    
    private lazy var scrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()
    
    private lazy var chatTextView: NSTextView = {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer()
        
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        
        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()
    
    private lazy var inputStackView: NSStackView = {
        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private lazy var inputTextField: NSTextField = {
        let textField = NSTextField()
        textField.placeholderString = "Введите сообщение..."
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()
    
    private lazy var sendButton: NSButton = {
        let button = NSButton()
        button.title = "➤ Отправить"
        button.bezelStyle = .push
        button.keyEquivalent = "\r"
        button.target = self
        button.action = #selector(sendMessageTapped)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private lazy var stopButton: NSButton = {
        let button = NSButton()
        button.title = "⏹ Стоп"
        button.bezelStyle = .push
        button.target = self
        button.action = #selector(stopStreamingTapped)
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private lazy var statusLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.textColor = NSColor.systemRed
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupBindings()
        setupNotifications()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.addSubview(settingsStackView)
        view.addSubview(scrollView)
        view.addSubview(inputStackView)
        view.addSubview(statusLabel)
        
        scrollView.documentView = chatTextView
        
        // Settings panel
        settingsStackView.addArrangedSubview(modelTextField)
        settingsStackView.addArrangedSubview(apiKeyTextField)
        settingsStackView.addArrangedSubview(temperatureSlider)
        settingsStackView.addArrangedSubview(temperatureLabel)
        settingsStackView.addArrangedSubview(topPSlider)
        settingsStackView.addArrangedSubview(topPLabel)
        settingsStackView.addArrangedSubview(streamSwitch)
        settingsStackView.addArrangedSubview(streamLabel)
        settingsStackView.addArrangedSubview(systemPromptTextField)
        settingsStackView.addArrangedSubview(clearChatButton)
        
        // Input area
        inputStackView.addArrangedSubview(inputTextField)
        inputStackView.addArrangedSubview(sendButton)
        inputStackView.addArrangedSubview(stopButton)
        
        // Constraints
        NSLayoutConstraint.activate([
            // Settings panel
            settingsStackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            settingsStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            settingsStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            settingsStackView.heightAnchor.constraint(equalToConstant: 30),
            
            // Chat area
            scrollView.topAnchor.constraint(equalTo: settingsStackView.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            scrollView.bottomAnchor.constraint(equalTo: inputStackView.topAnchor, constant: -10),
            
            // Input area
            inputStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            inputStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            inputStackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            inputStackView.heightAnchor.constraint(equalToConstant: 30),
            
            // Status label
            statusLabel.topAnchor.constraint(equalTo: inputStackView.bottomAnchor, constant: 5),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            
            // Text fields width
            modelTextField.widthAnchor.constraint(equalToConstant: 150),
            apiKeyTextField.widthAnchor.constraint(equalToConstant: 200),
            temperatureSlider.widthAnchor.constraint(equalToConstant: 100),
            temperatureLabel.widthAnchor.constraint(equalToConstant: 60),
            topPSlider.widthAnchor.constraint(equalToConstant: 100),
            topPLabel.widthAnchor.constraint(equalToConstant: 80),
            streamLabel.widthAnchor.constraint(equalToConstant: 60),
            systemPromptTextField.widthAnchor.constraint(equalToConstant: 200),
        ])
    }
    
    private func setupBindings() {
        // Temperature slider
        temperatureSlider.target = self
        temperatureSlider.action = #selector(temperatureChanged)
        
        // Top-P slider
        topPSlider.target = self
        topPSlider.action = #selector(topPChanged)
        
        // Stream switch
        streamSwitch.target = self
        streamSwitch.action = #selector(streamChanged)
        
        // Input field
        inputTextField.delegate = self
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResize),
            name: NSWindow.didResizeNotification,
            object: nil
        )
    }
    
    // MARK: - Actions
    
    @objc private func sendMessageTapped() {
        guard let inputText = inputTextField.currentEditor()?.string,
              !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        let userMessage = Message(role: .user, content: inputText)
        messages.append(userMessage)
        
        inputTextField.stringValue = ""
        appendMessageToChat(userMessage)
        scrollToBottom()
        
        chatState = .loading
        
        // Prepare messages with system prompt
        var apiMessages: [Message] = []
        if !settings.systemPrompt.isEmpty {
            apiMessages.append(Message(role: .system, content: settings.systemPrompt))
        }
        apiMessages.append(contentsOf: messages)
        
        llmService.sendMessage(
            messages: apiMessages,
            settings: settings,
            onToken: { [weak self] token in
                self?.appendTokenToLastAssistantMessage(token)
            },
            onComplete: { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let content):
                        // Ensure we have an assistant message
                        if self?.messages.last?.role != "assistant" {
                            self?.messages.append(Message(role: .assistant, content: content))
                        }
                        self?.chatState = .idle
                    case .failure(let error):
                        self?.chatState = .error(error.localizedDescription)
                    }
                }
            }
        )
    }
    
    @objc private func stopStreamingTapped() {
        llmService.cancelStreaming()
        chatState = .idle
    }
    
    @objc private func clearChatTapped() {
        messages.removeAll()
        chatTextView.string = ""
        statusLabel.isHidden = true
        statusLabel.stringValue = ""
    }
    
    @objc private func temperatureChanged() {
        settings.temperature = temperatureSlider.doubleValue
        temperatureLabel.stringValue = String(format: "T: %.2f", settings.temperature)
    }
    
    @objc private func topPChanged() {
        settings.topP = topPSlider.doubleValue
        topPLabel.stringValue = String(format: "Top-P: %.2f", settings.topP)
    }
    
    @objc private func streamChanged() {
        settings.stream = streamSwitch.state == .on
    }
    
    @objc private func windowDidResize() {
        scrollToBottom()
    }
    
    // MARK: - Chat UI Updates
    
    private func appendMessageToChat(_ message: Message) {
        let prefix: String
        let color: NSColor
        
        switch message.role {
        case "user":
            prefix = "👤 Вы"
            color = NSColor.systemBlue
        case "assistant":
            prefix = "🤖 Ассистент"
            color = NSColor.systemGreen
        case "system":
            prefix = "⚙️ Система"
            color = NSColor.systemGray
        default:
            prefix = message.role
            color = NSColor.textColor
        }
        
        let attributedString = NSMutableAttributedString()
        
        // Role label
        let roleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 12),
            .foregroundColor: color
        ]
        attributedString.append(NSAttributedString(string: "\n\(prefix):\n", attributes: roleAttributes))
        
        // Message content
        let contentAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.textColor
        ]
        attributedString.append(NSAttributedString(string: message.content, attributes: contentAttributes))
        
        chatTextView.textStorage?.append(attributedString)
    }
    
    private func appendTokenToLastAssistantMessage(_ token: String) {
        // Check if we need to create a new assistant message
        if messages.last?.role != "assistant" {
            messages.append(Message(role: .assistant, content: token))
            
            // Add assistant header
            let attributedString = NSMutableAttributedString()
            let roleAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 12),
                .foregroundColor: NSColor.systemGreen
            ]
            attributedString.append(NSAttributedString(string: "\n🤖 Ассистент:\n", attributes: roleAttributes))
            
            let contentAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.textColor
            ]
            attributedString.append(NSAttributedString(string: token, attributes: contentAttributes))
            
            chatTextView.textStorage?.append(attributedString)
        } else {
            // Append to existing assistant message
            messages[messages.count - 1].content += token
            
            // Append token to text view
            let contentAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.textColor
            ]
            let attributedString = NSAttributedString(string: token, attributes: contentAttributes)
            chatTextView.textStorage?.append(attributedString)
        }
        
        scrollToBottom()
    }
    
    private func scrollToBottom() {
        let range = NSRange(location: chatTextView.string.count - 1, length: 1)
        chatTextView.scrollRangeToVisible(range)
    }
    
    private func updateStateUI() {
        switch chatState {
        case .idle:
            sendButton.isEnabled = true
            sendButton.title = "➤ Отправить"
            stopButton.isHidden = true
            inputTextField.isEnabled = true
            statusLabel.isHidden = true
            statusLabel.stringValue = ""
        case .loading:
            sendButton.isEnabled = false
            sendButton.title = "⏳ Отправка..."
            stopButton.isHidden = false
            inputTextField.isEnabled = false
            statusLabel.isHidden = true
            statusLabel.stringValue = ""
        case .error(let message):
            sendButton.isEnabled = true
            sendButton.title = "➤ Отправить"
            stopButton.isHidden = true
            inputTextField.isEnabled = true
            statusLabel.isHidden = false
            statusLabel.stringValue = "❌ \(message)"
        }
    }
}

// MARK: - NSTextFieldDelegate

extension ViewController: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            sendMessageTapped()
            return true
        }
        return false
    }
}

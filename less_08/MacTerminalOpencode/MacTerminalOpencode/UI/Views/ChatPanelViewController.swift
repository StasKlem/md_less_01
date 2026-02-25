//
//  ChatPanelViewController.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 22.02.2026.
//

import AppKit
import Combine

/// Main chat panel displaying message history and input field
final class ChatPanelViewController: NSViewController {
    
    private let scrollView = NSScrollView()
    private let messageTextView = NSTextView()
    private let inputTextField = NSTextField()
    private let sendButton = NSButton()
    private let clearButton = NSButton()
    private let activityIndicator = NSProgressIndicator()
    
    private var viewModel: ChatViewModel?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Lifecycle
    
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
    }
    
    // MARK: - Configuration
    
    func configure(with viewModel: ChatViewModel) {
        self.viewModel = viewModel
        
        viewModel.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleViewModelEvent(event)
            }
        }
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        view.wantsLayer = true
        
        setupScrollView()
        setupInputField()
        setupButtons()
        setupActivityIndicator()
    }
    
    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        
        messageTextView.isEditable = false
        messageTextView.isSelectable = true
        messageTextView.autoresizingMask = [.width]
        messageTextView.textContainerInset = NSSize(width: 8, height: 8)
        messageTextView.font = .systemFont(ofSize: 13)
        messageTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        
        scrollView.documentView = messageTextView
        view.addSubview(scrollView)
    }
    
    private func setupInputField() {
        inputTextField.translatesAutoresizingMaskIntoConstraints = false
        inputTextField.placeholderString = "Type your message..."
        inputTextField.bezelStyle = .roundedBezel
        inputTextField.isBezeled = true
        inputTextField.delegate = self
        view.addSubview(inputTextField)
    }
    
    private func setupButtons() {
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.title = "Send"
        sendButton.bezelStyle = .rounded
        sendButton.target = self
        sendButton.action = #selector(sendButtonClicked)
        sendButton.keyEquivalent = "\r"
        view.addSubview(sendButton)
        
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.title = "Clear"
        clearButton.bezelStyle = .rounded
        clearButton.target = self
        clearButton.action = #selector(clearButtonClicked)
        view.addSubview(clearButton)
    }
    
    private func setupActivityIndicator() {
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.style = .spinning
        activityIndicator.controlSize = .small
        activityIndicator.isHidden = true
        view.addSubview(activityIndicator)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: inputTextField.topAnchor, constant: -12),
            
            inputTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            inputTextField.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            inputTextField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            
            sendButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            sendButton.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -8),
            sendButton.widthAnchor.constraint(equalToConstant: 70),
            
            clearButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            clearButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            clearButton.widthAnchor.constraint(equalToConstant: 70),
            
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    // MARK: - Actions
    
    @objc private func sendButtonClicked() {
        let text = inputTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[ChatPanel] Send button clicked, text: '\(text)'")
        guard !text.isEmpty else { return }
        
        viewModel?.sendMessage(text)
        inputTextField.stringValue = ""
    }
    
    @objc private func clearButtonClicked() {
        viewModel?.clearChat()
    }
    
    // MARK: - ViewModel Events

    private func handleViewModelEvent(_ event: ChatViewModelEvent) {
        print("[ChatPanel] Received event: \(event)")
        switch event {
        case .messagesUpdated(let messages):
            print("[ChatPanel] Updating display with \(messages.count) messages")
            updateMessagesDisplay(messages)
        case .processingStateChanged(let isProcessing):
            updateProcessingState(isProcessing)
        case .errorOccurred(let error):
            showError(error)
        case .messageSent:
            scrollToBottom()
        }
    }

    private func updateMessagesDisplay(_ messages: [MessageDisplayItem]) {
        let fullText = NSMutableAttributedString()

        for message in messages {
            let header = NSAttributedString(
                string: "\(message.role.displayName):\n",
                attributes: [
                    .font: NSFont.boldSystemFont(ofSize: 13),
                    .foregroundColor: message.role.color
                ]
            )
            fullText.append(header)
            fullText.append(message.content)
            fullText.append(NSAttributedString(string: "\n\n"))

            if let error = message.error {
                let errorText = NSAttributedString(
                    string: "Error: \(error)\n",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 12),
                        .foregroundColor: NSColor.systemRed
                    ]
                )
                fullText.append(errorText)
            }
        }

        messageTextView.textStorage?.setAttributedString(fullText)
        messageTextView.needsDisplay = true
        scrollToBottom()
    }
    
    private func updateProcessingState(_ isProcessing: Bool) {
        sendButton.isEnabled = !isProcessing
        inputTextField.isEnabled = !isProcessing
        
        if isProcessing {
            activityIndicator.startAnimation(nil)
            activityIndicator.isHidden = false
        } else {
            activityIndicator.stopAnimation(nil)
            activityIndicator.isHidden = true
        }
    }
    
    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: view.window!)
    }
    
    private func scrollToBottom() {
        guard let textStorage = messageTextView.textStorage, textStorage.length > 0 else { return }
        let range = NSRange(location: max(0, textStorage.length - 1), length: 1)
        messageTextView.scrollRangeToVisible(range)
    }
}

extension ChatPanelViewController: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        print("[ChatPanel] doCommandBy: \(commandSelector)")
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if NSEvent.modifierFlags.contains(.shift) {
                return false
            }
            print("[ChatPanel] Enter pressed, sending message")
            sendButtonClicked()
            return true
        }
        return false
    }
}

private extension MessageRole {
    var displayName: String {
        switch self {
        case .user: return "You"
        case .assistant: return "Assistant"
        case .system: return "System"
        }
    }
    
    var color: NSColor {
        switch self {
        case .user: return .systemBlue
        case .assistant: return .systemGreen
        case .system: return .systemOrange
        }
    }
}

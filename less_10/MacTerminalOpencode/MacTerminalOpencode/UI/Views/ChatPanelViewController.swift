//
//  ChatPanelViewController.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 22.02.2026.
//

import AppKit

/// Main chat panel displaying message history and input field
final class ChatPanelViewController: NSViewController {

    // MARK: - UI Constants

    private enum Layout {
        static let horizontalInset: CGFloat = 12
        static let verticalInset: CGFloat = 12
        static let spacing: CGFloat = 8
        static let buttonWidth: CGFloat = 70
    }

    private enum Style {
        static let contentFontSize: CGFloat = 13
        static let errorFontSize: CGFloat = 12
        static let summaryHighlightColor: NSColor = .systemPurple
        static let messageSeparator = "\n\n"
    }

    private let scrollView = NSScrollView()
    private let messageTextView = NSTextView()
    private let inputTextField = NSTextField()
    private let sendButton = NSButton()
    private let clearButton = NSButton()
    private let activityIndicator = NSProgressIndicator()

    private var viewModel: ChatViewModel?

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
        messageTextView.font = .systemFont(ofSize: Style.contentFontSize)
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
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: Layout.verticalInset),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.horizontalInset),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.horizontalInset),
            scrollView.bottomAnchor.constraint(equalTo: inputTextField.topAnchor, constant: -Layout.verticalInset),

            inputTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.horizontalInset),
            inputTextField.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Layout.verticalInset),
            inputTextField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -Layout.spacing),

            sendButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Layout.verticalInset),
            sendButton.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -Layout.spacing),
            sendButton.widthAnchor.constraint(equalToConstant: Layout.buttonWidth),

            clearButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Layout.verticalInset),
            clearButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.horizontalInset),
            clearButton.widthAnchor.constraint(equalToConstant: Layout.buttonWidth),

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
        messages.forEach { appendMessage($0, to: fullText) }
        messageTextView.textStorage?.setAttributedString(fullText)
        messageTextView.needsDisplay = true
        scrollToBottom()
    }

    private func appendMessage(_ message: MessageDisplayItem, to fullText: NSMutableAttributedString) {
        let isSummary = message.isSummaryMessage
        fullText.append(header(for: message, isSummary: isSummary))
        fullText.append(content(for: message, isSummary: isSummary))
        fullText.append(NSAttributedString(string: Style.messageSeparator))

        if let error = message.error {
            fullText.append(errorText(for: error))
        }
    }

    private func header(for message: MessageDisplayItem, isSummary: Bool) -> NSAttributedString {
        NSAttributedString(
            string: "\(message.role.displayName):\n",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: Style.contentFontSize),
                .foregroundColor: isSummary ? Style.summaryHighlightColor : message.role.color
            ]
        )
    }

    private func content(for message: MessageDisplayItem, isSummary: Bool) -> NSAttributedString {
        guard isSummary else { return message.content }

        let attributedContent = NSMutableAttributedString(attributedString: message.content)
        let range = NSRange(location: 0, length: attributedContent.length)
        attributedContent.addAttribute(.foregroundColor, value: Style.summaryHighlightColor, range: range)
        attributedContent.addAttribute(.font, value: NSFont.systemFont(ofSize: Style.contentFontSize), range: range)
        return attributedContent
    }

    private func errorText(for error: String) -> NSAttributedString {
        NSAttributedString(
            string: "Error: \(error)\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: Style.errorFontSize),
                .foregroundColor: NSColor.systemRed
            ]
        )
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

        guard let window = view.window else {
            alert.runModal()
            return
        }
        alert.beginSheetModal(for: window)
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

private extension MessageDisplayItem {
    var isSummaryMessage: Bool {
        role == .system && rawContent.contains("резюме")
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

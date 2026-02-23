//
//  MessageInputView.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import AppKit
import Combine

/// Вид ввода сообщения с кнопкой отправки.
final class MessageInputView: NSView {
    
    // MARK: - Properties
    
    private let textView: NSTextView
    private let scrollView: NSScrollView
    private let sendButton: NSButton
    private let cancelButton: NSButton
    
    private var heightConstraint: NSLayoutConstraint?
    
    private let maxHeight: CGFloat = 150
    private let minHeight: CGFloat = 44
    
    // MARK: - Callbacks
    
    var onSend: (() -> Void)?
    var onCancel: (() -> Void)?
    
    // MARK: - Published Properties
    
    var text: String {
        get { textView.string }
        set { textView.string = newValue }
    }
    
    var placeholderString: String = "Введите сообщение..." {
        didSet {
            updatePlaceholder()
        }
    }
    
    var isLoading: Bool = false {
        didSet {
            updateButtons()
        }
    }
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        textView = NSTextView()
        scrollView = NSScrollView()
        sendButton = NSButton()
        cancelButton = NSButton()
        
        super.init(frame: frameRect)
        
        setupScrollView()
        setupTextView()
        setupButtons()
        setupLayout()
        setupBindings()
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    
    private func setupScrollView() {
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
    }
    
    private func setupTextView() {
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainer?.lineFragmentPadding = 8
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.font = NSFont.systemFont(ofSize: 14)
        
        scrollView.documentView = textView
    }
    
    private func setupButtons() {
        // Кнопка отправки
        sendButton.title = "Send"
        sendButton.bezelStyle = .rounded
        sendButton.keyEquivalent = "\r"
        sendButton.target = self
        sendButton.action = #selector(sendTapped)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        
        // Кнопка отмены
        cancelButton.title = "Stop"
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)
        cancelButton.isHidden = true
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
    }
    
    private func setupLayout() {
        addSubview(scrollView)
        addSubview(sendButton)
        addSubview(cancelButton)
        
        let padding: CGFloat = 8
        
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
            scrollView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -padding),
            
            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            sendButton.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 70),
            sendButton.heightAnchor.constraint(equalToConstant: 28),
            
            cancelButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            cancelButton.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 70),
            cancelButton.heightAnchor.constraint(equalToConstant: 28)
        ])
        
        // Ограничение высоты
        heightConstraint = heightAnchor.constraint(equalToConstant: minHeight)
        heightConstraint?.isActive = true
    }
    
    private func setupBindings() {
        // Наблюдение за изменениями текста
        NotificationCenter.default.publisher(
            for: NSText.didChangeNotification,
            object: textView
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.adjustHeight()
        }
        .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Actions
    
    @objc private func sendTapped() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        onSend?()
    }
    
    @objc private func cancelTapped() {
        onCancel?()
    }
    
    // MARK: - Layout
    
    private func adjustHeight() {
        guard let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else { return }
        
        layoutManager.ensureLayout(for: textContainer)
        
        let contentHeight = layoutManager.usedRect(for: textContainer).height
        let textHeight = contentHeight + textView.textContainerInset.height * 2
        
        let newHeight = max(minHeight, min(maxHeight, textHeight + 16))
        
        heightConstraint?.constant = newHeight
        needsLayout = true
    }
    
    private func updatePlaceholder() {
        // NSTextView не имеет встроенного placeholder, используем текстовый цвет
        if text.isEmpty {
            textView.textColor = .placeholderTextColor
        } else {
            textView.textColor = .textColor
        }
    }
    
    private func updateButtons() {
        sendButton.isHidden = isLoading
        cancelButton.isHidden = !isLoading
        
        if isLoading {
            cancelButton.becomeFirstResponder()
        }
    }
    
    // MARK: - Focus
    
    func focus() {
        window?.makeFirstResponder(textView)
    }
    
    func clear() {
        text = ""
        adjustHeight()
    }
}

// MARK: - NSControl Extension

extension MessageInputView {
    var isEnabled: Bool {
        get { textView.isEditable }
        set { textView.isEditable = newValue }
    }
}

//
//  MessageCellView.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import AppKit

/// Ячейка для отображения сообщения в чате.
final class MessageCellView: NSTableCellView {
    
    // MARK: - Properties
    
    private let textView: NSTextView
    private let containerView: NSView
    private let errorLabel: NSTextField
    
    private var isUserMessage: Bool = false
    
    // MARK: - Colors
    
    private enum Colors {
        static let userBackground = NSColor.controlAccentColor.withAlphaComponent(0.15)
        static let assistantBackground = NSColor.textBackgroundColor
        static let userText = NSColor.textColor
        static let assistantText = NSColor.textColor
        static let errorBackground = NSColor.systemRed.withAlphaComponent(0.1)
        static let errorText = NSColor.systemRed
    }
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        textView = NSTextView()
        containerView = NSView()
        errorLabel = NSTextField(labelWithString: "")
        
        super.init(frame: frameRect)
        
        setupTextView()
        setupErrorLabel()
        setupContainerView()
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    
    private func setupTextView() {
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 12, height: 8)
        
        // Отключение контекстного меню
        textView.menu = nil
    }
    
    private func setupErrorLabel() {
        errorLabel.isHidden = true
        errorLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        errorLabel.textColor = Colors.errorText
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.maximumNumberOfLines = 2
    }
    
    private func setupContainerView() {
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 12
        containerView.layer?.masksToBounds = true
    }
    
    // MARK: - Layout

    override func layout() {
        super.layout()

        let padding: CGFloat = 8
        let horizontalPadding: CGFloat = 12

        // Определяем ширину контента
        let contentWidth = bounds.width - horizontalPadding * 2 - padding * 2

        // Размещаем контейнер
        let containerWidth: CGFloat
        if isUserMessage {
            containerWidth = min(contentWidth, textView.string.boundingRect(
                with: NSSize(width: contentWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).width + 24)
        } else {
            containerWidth = contentWidth
        }

        let textViewHeight = textView.string.isEmpty ? 20 : textView.bounds.height
        let containerHeight = textViewHeight + 16

        if isUserMessage {
            // Пользователь: выравнивание вправо
            containerView.frame = NSRect(
                x: bounds.width - containerWidth - padding - horizontalPadding,
                y: padding,
                width: containerWidth,
                height: containerHeight
            )
        } else {
            // Ассистент: выравнивание влево
            containerView.frame = NSRect(
                x: horizontalPadding,
                y: padding,
                width: containerWidth,
                height: containerHeight
            )
        }

        textView.frame = NSRect(
            x: 8,
            y: 8,
            width: containerWidth - 16,
            height: textViewHeight
        )
        
        // Размещаем label ошибки
        if !errorLabel.isHidden {
            errorLabel.frame = NSRect(
                x: containerView.frame.origin.x,
                y: containerView.frame.origin.y - 20,
                width: containerWidth,
                height: 18
            )
        }
    }
    
    // MARK: - Configuration
    
    /// Настроить ячейку с сообщением
    func configure(with message: Message, maxWidth: CGFloat = 400) {
        isUserMessage = message.isUser
        
        // Настройка стилей
        if isUserMessage {
            containerView.layer?.backgroundColor = Colors.userBackground.cgColor
            textView.textColor = Colors.userText
        } else {
            containerView.layer?.backgroundColor = Colors.assistantBackground.cgColor
            textView.textColor = Colors.assistantText
        }
        
        // Установка текста с базовым Markdown форматированием
        let attributedText = message.content.toAttributedString(
            baseFont: NSFont.systemFont(ofSize: 13)
        )
        textView.textStorage?.setAttributedString(attributedText)

        // Обновление размера
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        
        // Настройка ошибки
        if let error = message.error {
            errorLabel.stringValue = "⚠️ \(error)"
            errorLabel.isHidden = false
            containerView.layer?.backgroundColor = Colors.errorBackground.cgColor
        } else {
            errorLabel.isHidden = true
        }
        
        needsLayout = true
    }
    
    /// Очистить ячейку
    override func prepareForReuse() {
        textView.string = ""
        errorLabel.isHidden = true
        containerView.layer?.backgroundColor = nil
    }
}

// MARK: - Helper Extension

private extension String {
    func boundingRect(with size: NSSize, options: NSString.DrawingOptions = []) -> NSRect {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13)
        ]
        return (self as NSString).boundingRect(with: size, options: options, attributes: attributes)
    }
}

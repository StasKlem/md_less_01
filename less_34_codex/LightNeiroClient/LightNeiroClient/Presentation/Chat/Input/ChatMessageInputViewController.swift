import Cocoa

final class ChatMessageInputViewController: NSViewController {
    var onSend: ((String) -> Void)?

    private let textView = NSTextView()
    private let sendButton = NSButton(title: "Отправить", target: nil, action: nil)

    override func loadView() {
        let rootView = NSView()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
    }

    private func setupLayout() {
        let titleLabel = NSTextField(labelWithString: "Новое сообщение")
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.font = .systemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = .textBackgroundColor
        textView.string = ""
        textView.delegate = self
        textView.textContainer = textContainer
        sendButton.isEnabled = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = true
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        sendButton.target = self
        sendButton.action = #selector(sendCurrentMessage)
        sendButton.controlSize = .large
        sendButton.bezelStyle = .rounded
        sendButton.translatesAutoresizingMaskIntoConstraints = false

        let footerLabel = NSTextField(labelWithString: "Cmd+Enter пока не настроен, используйте кнопку отправки.")
        footerLabel.font = .systemFont(ofSize: 11, weight: .regular)
        footerLabel.textColor = .secondaryLabelColor

        let buttonRow = NSStackView(views: [NSView(), sendButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [titleLabel, scrollView, buttonRow, footerLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            scrollView.heightAnchor.constraint(equalToConstant: 90),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),

            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    @objc private func sendCurrentMessage() {
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            NSSound.beep()
            return
        }

        onSend?(text)
        textView.string = ""
    }
}

extension ChatMessageInputViewController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        sendButton.isEnabled = !textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

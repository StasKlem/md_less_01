import Cocoa

// MARK: - Message Input View Delegate

protocol MessageInputViewDelegate: AnyObject {
    func messageInputView(_ view: MessageInputView, didSubmitMessage message: String)
    func messageInputViewDidTapStop(_ view: MessageInputView)
    func messageInputViewDidTapClear(_ view: MessageInputView)
}

// MARK: - Message Input View

final class MessageInputView: NSView {

    // MARK: - Properties

    weak var delegate: MessageInputViewDelegate?

    var placeholderString: String? {
        get { inputTextField.placeholderString }
        set { inputTextField.placeholderString = newValue }
    }

    var messageText: String {
        get { inputTextField.stringValue }
        set { inputTextField.stringValue = newValue }
    }

    var isSending: Bool = false {
        didSet {
            updateState()
        }
    }

    var sendButtonTitle: String = "➤ Отправить" {
        didSet {
            sendButton.title = sendButtonTitle
        }
    }

    // MARK: - UI Elements

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
        button.action = #selector(sendTapped)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var stopButton: NSButton = {
        let button = NSButton()
        button.title = "⏹ Стоп"
        button.bezelStyle = .push
        button.target = self
        button.action = #selector(stopTapped)
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var clearButton: NSButton = {
        let button = NSButton()
        button.title = "🗑️"
        button.bezelStyle = .smallSquare
        button.target = self
        button.action = #selector(clearTapped)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.toolTip = "Очистить"
        return button
    }()

    private lazy var stackView: NSStackView = {
        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.spacing = 10
        stackView.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        setupBindings()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        setupBindings()
    }
    
    // MARK: - Setup

    private func setupUI() {
        addSubview(stackView)

        stackView.addArrangedSubview(inputTextField)
        stackView.addArrangedSubview(sendButton)
        stackView.addArrangedSubview(stopButton)
        stackView.addArrangedSubview(clearButton)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),

            sendButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
            stopButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            clearButton.widthAnchor.constraint(equalToConstant: 40),
        ])
    }
    
    private func setupBindings() {
        inputTextField.delegate = self
    }
    
    private func updateState() {
        if isSending {
            sendButton.isEnabled = false
            sendButton.title = "⏳ Отправка..."
            stopButton.isHidden = false
            inputTextField.isEnabled = false
        } else {
            sendButton.isEnabled = true
            sendButton.title = sendButtonTitle
            stopButton.isHidden = true
            inputTextField.isEnabled = true
        }
    }
    
    // MARK: - Actions
    
    @objc private func sendTapped() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        delegate?.messageInputView(self, didSubmitMessage: messageText)
        messageText = ""
    }
    
    @objc private func stopTapped() {
        delegate?.messageInputViewDidTapStop(self)
    }
    
    @objc private func clearTapped() {
        delegate?.messageInputViewDidTapClear(self)
    }
    
    // MARK: - Public Methods
    
    func focus() {
        window?.makeFirstResponder(inputTextField)
    }
    
    func clear() {
        messageText = ""
    }
}

// MARK: - NSTextFieldDelegate

extension MessageInputView: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            sendTapped()
            return true
        }
        return false
    }
}

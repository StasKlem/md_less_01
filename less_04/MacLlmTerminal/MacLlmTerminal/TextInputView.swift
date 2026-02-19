import Cocoa

// MARK: - Text Input View Delegate

protocol TextInputViewDelegate: AnyObject {
    func textInputView(_ view: TextInputView, didChangeText text: String)
}

// MARK: - Text Input View

final class TextInputView: NSView {

    // MARK: - Properties

    weak var delegate: TextInputViewDelegate?
    
    // Храним значение отдельно для NSSecureTextField
    private var storedValue: String = ""

    var label: String {
        get { titleLabel.stringValue }
        set { titleLabel.stringValue = newValue }
    }

    var placeholder: String? {
        get { textField.placeholderString }
        set { textField.placeholderString = newValue }
    }

    var text: String {
        get {
//            if isSecure {
//                return storedValue
//            }
            return textField.stringValue
        }
        set {
            storedValue = newValue
            textField.stringValue = newValue
        }
    }

    var isSecure: Bool = false {
        didSet {
            recreateTextField()
        }
    }

    var height: CGFloat = 22 {
        didSet {
            heightConstraint?.constant = height
        }
    }

    private weak var heightConstraint: NSLayoutConstraint?
    private var textFieldConstraints: [NSLayoutConstraint] = []

    // MARK: - UI Elements

    private lazy var titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private var textField: NSTextField = {
        let field = NSTextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    private lazy var stackView: NSStackView = {
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.spacing = 5
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        setupTextField()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        setupTextField()
    }

    // MARK: - Setup

    private func setupUI() {
        addSubview(stackView)

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(textField)

        heightConstraint = textField.heightAnchor.constraint(equalToConstant: height)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            heightConstraint!,

            textField.widthAnchor.constraint(equalTo: stackView.widthAnchor),
        ])
    }

    private func setupTextField() {
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.target = self
        textField.action = #selector(textChanged)
    }
    
    private func recreateTextField() {
        // Сохраняем текущее значение
        let currentValue = isSecure ? storedValue : textField.stringValue
        storedValue = currentValue
        
        // Удаляем старое поле из stackView
        stackView.removeArrangedSubview(textField)
        textField.removeFromSuperview()
        
        // Создаём новое поле
        if isSecure {
            textField = NSSecureTextField()
        } else {
            textField = NSTextField()
        }
        
        // Восстанавливаем значение и настройки
        textField.stringValue = currentValue
        textField.placeholderString = placeholder
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.target = self
        textField.action = #selector(textChanged)
        
        // Вставляем новое поле на место старого
        stackView.insertArrangedSubview(textField, at: 1)
        
        // Обновляем constraints
        NSLayoutConstraint.activate([
            textField.heightAnchor.constraint(equalToConstant: height),
            textField.widthAnchor.constraint(equalTo: stackView.widthAnchor),
        ])
    }
    
    // MARK: - Actions
    
    @objc private func textChanged() {
        let currentValue = isSecure ? textField.stringValue : textField.stringValue
        if isSecure {
            storedValue = textField.stringValue
        }
        delegate?.textInputView(self, didChangeText: currentValue)
    }

    // MARK: - Public Methods

    func focus() {
        window?.makeFirstResponder(textField)
    }

    func clear() {
        textField.stringValue = ""
    }
}

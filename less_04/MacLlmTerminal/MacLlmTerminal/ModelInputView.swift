import Cocoa

// MARK: - Model Input View Delegate

protocol ModelInputViewDelegate: AnyObject {
    func modelInputView(_ view: ModelInputView, didSelectModel model: String)
}

// MARK: - Model Input View

final class ModelInputView: NSView {

    // MARK: - Properties

    weak var delegate: ModelInputViewDelegate?

    var selectedModel: AvailableModel {
        get {
            guard let selectedItem = popupButton.selectedItem,
                  let model = AvailableModel.allCases.first(where: { $0.displayName == selectedItem.title }) else {
                return .defaultModel
            }
            return model
        }
        set {
            if let index = AvailableModel.allCases.firstIndex(of: newValue) {
                popupButton.selectItem(at: index)
            }
        }
    }

    // MARK: - UI Elements

    private lazy var titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Модель:")
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var popupButton: NSPopUpButton = {
        let button = NSPopUpButton(title: "", target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        
        // Добавляем все доступные модели
        for model in AvailableModel.allCases {
            button.addItem(withTitle: model.displayName)
            button.lastItem?.tag = AvailableModel.allCases.firstIndex(of: model) ?? 0
        }
        
        // Устанавливаем модель по умолчанию
        if let defaultIndex = AvailableModel.allCases.firstIndex(of: .defaultModel) {
            button.selectItem(at: defaultIndex)
        }
        
        button.target = self
        button.action = #selector(modelChanged(_:))
        
        return button
    }()

    private lazy var stackView: NSStackView = {
        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        setupModel()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        setupModel()
    }
    
    // MARK: - Setup Model
    
    private func setupModel() {
        // Устанавливаем модель по умолчанию
        selectedModel = .defaultModel
    }

    // MARK: - Setup

    private func setupUI() {
        addSubview(stackView)

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(popupButton)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            popupButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 200)
        ])
    }

    // MARK: - Actions

    @objc private func modelChanged(_ sender: NSPopUpButton) {
        delegate?.modelInputView(self, didSelectModel: selectedModel.rawValue)
    }

    // MARK: - Public Methods

    func setModel(_ model: AvailableModel) {
        selectedModel = model
    }
}

import Cocoa

// MARK: - Settings View Controller

final class SettingsViewController: NSViewController {
    
    // MARK: - Constants
    
    private enum Constants {
        // Layout
        static let stackViewSpacing: CGFloat = 16
        static let stackViewEdgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        static let sectionSpacing: CGFloat = 5
        static let streamSectionSpacing: CGFloat = 10
        static let elementTopPadding: CGFloat = 8
        static let elementBottomPadding: CGFloat = 8
        
        // Fonts
        static let titleFont = NSFont.boldSystemFont(ofSize: 16)
        static let labelFont = NSFont.systemFont(ofSize: 12, weight: .medium)
        
        // Sizes
        static let inputHeight: CGFloat = 22
        static let systemPromptHeight: CGFloat = 60
        
        // Slider ranges
        static let temperatureMin: Double = 0
        static let temperatureMax: Double = 2
        static let topPMin: Double = 0
        static let topPMax: Double = 1
    }

    // MARK: - Properties

    var onSettingsChanged: ((ChatSettings) -> Void)?
    private var settings = ChatSettings.default
    
    private var isDebugEnabled: Bool = true

    // MARK: - UI Elements

    private lazy var scrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    private lazy var contentView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var stackView: NSStackView = {
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.spacing = Constants.stackViewSpacing
        stackView.edgeInsets = Constants.stackViewEdgeInsets
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.distribution = .fill
//        stackView.alignment = .top
        return stackView
    }()

    // MARK: - Title

    private lazy var titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "⚙️ Настройки")
        label.font = Constants.titleFont
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var separator: NSBox = {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }()
    
    private lazy var titleContainer: NSStackView = {
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.spacing = Constants.elementTopPadding
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    // MARK: - Model Input

    private lazy var modelInputView: ModelInputView = {
        let view = ModelInputView()
        view.delegate = self
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - API Key Input

    private lazy var apiKeyInputView: TextInputView = {
        let view = TextInputView()
        view.label = "API Ключ"
        view.placeholder = "sk-..."
        view.isSecure = true
        view.height = Constants.inputHeight
        view.delegate = self
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - Temperature Slider

    private lazy var temperatureSection: NSStackView = {
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.spacing = Constants.sectionSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    private lazy var temperatureLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Температура: \(String(format: "%.2f", ChatSettings.default.temperature))")
        label.font = Constants.labelFont
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var temperatureSlider: NSSlider = {
        let slider = NSSlider()
        slider.minValue = Constants.temperatureMin
        slider.maxValue = Constants.temperatureMax
        slider.doubleValue = ChatSettings.default.temperature
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.target = self
        slider.action = #selector(temperatureChanged)
        return slider
    }()

    // MARK: - Top-P Slider

    private lazy var topPSection: NSStackView = {
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.spacing = Constants.sectionSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    private lazy var topPLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Top-P: \(String(format: "%.2f", ChatSettings.default.topP))")
        label.font = Constants.labelFont
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var topPSlider: NSSlider = {
        let slider = NSSlider()
        slider.minValue = Constants.topPMin
        slider.maxValue = Constants.topPMax
        slider.doubleValue = ChatSettings.default.topP
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.target = self
        slider.action = #selector(topPChanged)
        return slider
    }()

    // MARK: - Stream Switch

    private lazy var streamSection: NSStackView = {
        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.spacing = Constants.streamSectionSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    private lazy var streamLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Стриминг")
        label.font = Constants.labelFont
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var streamSwitch: NSSwitch = {
        let switchControl = NSSwitch()
        switchControl.state = ChatSettings.default.stream ? .on : .off
        switchControl.translatesAutoresizingMaskIntoConstraints = false
        switchControl.target = self
        switchControl.action = #selector(streamChanged)
        return switchControl
    }()

    // MARK: - System Prompt Input

    private lazy var systemPromptInputView: TextInputView = {
        let view = TextInputView()
        view.label = "Системный промт"
        view.placeholder = "You are a helpful assistant."
        view.text = ChatSettings.default.systemPrompt
        view.height = Constants.systemPromptHeight
        view.delegate = self
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        // Устанавливаем текущую модель в ModelInputView
        if let defaultModel = AvailableModel.allCases.first(where: { $0.rawValue == settings.model }) {
            modelInputView.setModel(defaultModel)
        }
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.addSubview(scrollView)
        scrollView.documentView = contentView
        contentView.addSubview(stackView)

        // Добавляем секции в стек
        titleContainer.addArrangedSubview(titleLabel)
        titleContainer.addArrangedSubview(separator)
        
        stackView.addArrangedSubview(titleContainer)
        stackView.addArrangedSubview(modelInputView)
        stackView.addArrangedSubview(apiKeyInputView)
        stackView.addArrangedSubview(temperatureSection)
        temperatureSection.addArrangedSubview(temperatureLabel)
        temperatureSection.addArrangedSubview(temperatureSlider)

        stackView.addArrangedSubview(topPSection)
        topPSection.addArrangedSubview(topPLabel)
        topPSection.addArrangedSubview(topPSlider)

        stackView.addArrangedSubview(streamSection)
        streamSection.addArrangedSubview(streamLabel)
        streamSection.addArrangedSubview(streamSwitch)

        stackView.addArrangedSubview(systemPromptInputView)

        // Constraints - все view растягиваются по ширине
        NSLayoutConstraint.activate([
            titleContainer.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            titleLabel.widthAnchor.constraint(equalTo: titleContainer.widthAnchor),
            separator.widthAnchor.constraint(equalTo: titleContainer.widthAnchor),
            modelInputView.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            apiKeyInputView.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            temperatureSection.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            topPSection.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            streamSection.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            systemPromptInputView.widthAnchor.constraint(equalTo: stackView.widthAnchor),

            temperatureSlider.widthAnchor.constraint(equalTo: temperatureSection.widthAnchor),
            topPSlider.widthAnchor.constraint(equalTo: topPSection.widthAnchor),
        ])
        
        // Constraints
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),

//            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
//            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
//            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
//            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Constants.stackViewSpacing),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Constants.stackViewSpacing),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Constants.stackViewSpacing),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -Constants.stackViewSpacing)
        ])
        
        if isDebugEnabled {
            apiKeyInputView.text = ""
        }
    }
    
    // MARK: - Actions
    
    @objc private func temperatureChanged() {
        settings.temperature = temperatureSlider.doubleValue.rounded(toPlaces: 1)
        temperatureLabel.stringValue = "Температура: \(String(format: "%.2f", settings.temperature))"
        notifySettingsChanged()
    }
    
    @objc private func topPChanged() {
        settings.topP = topPSlider.doubleValue
        topPLabel.stringValue = "Top-P: \(String(format: "%.2f", settings.topP))"
        notifySettingsChanged()
    }
    
    @objc private func streamChanged() {
        settings.stream = streamSwitch.state == .on
        notifySettingsChanged()
    }
    
    private func notifySettingsChanged() {
        onSettingsChanged?(settings)
    }
    
    // MARK: - Public Methods
    
    func getSettings() -> ChatSettings {
        return settings
    }
    
    func getApiKey() -> String {
        return apiKeyInputView.text
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

// MARK: - TextInputViewDelegate

extension SettingsViewController: TextInputViewDelegate {
    func textInputView(_ view: TextInputView, didChangeText text: String) {
        if view == apiKeyInputView {
            // API key is handled separately
        } else if view == systemPromptInputView {
            settings.systemPrompt = text
        }
        notifySettingsChanged()
    }
}

// MARK: - ModelInputViewDelegate

extension SettingsViewController: ModelInputViewDelegate {
    func modelInputView(_ view: ModelInputView, didSelectModel model: String) {
        settings.model = model
        notifySettingsChanged()
    }
}

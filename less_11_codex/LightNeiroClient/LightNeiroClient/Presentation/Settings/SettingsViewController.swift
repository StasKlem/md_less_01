import Cocoa
import Combine

final class SettingsViewController: NSViewController {
    private let viewModel: SettingsViewModel
    private var cancellables = Set<AnyCancellable>()

    private let modelPopup = NSPopUpButton()
    private let contextStrategyPopup = NSPopUpButton()
    private let temperatureSlider = NSSlider(value: 0.4, minValue: 0, maxValue: 1.2, target: nil, action: nil)
    private let temperatureLabel = NSTextField(labelWithString: "Temperature: 0.40")
    private let windowSlider = NSSlider(value: 12, minValue: 4, maxValue: 30, target: nil, action: nil)
    private let windowLabel = NSTextField(labelWithString: "Window: 12")
    private let apiKeyField = NSSecureTextField()
    private let saveAPIKeyButton = NSButton(title: "Save API Key", target: nil, action: nil)
    private let apiKeyStatusLabel = NSTextField(labelWithString: "")

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bind()
    }

    private func setupUI() {
        modelPopup.addItems(withTitles: LLMModel.allCases.map { $0.rawValue })
        contextStrategyPopup.addItems(withTitles: ContextStrategy.allCases.map { $0.rawValue })

        modelPopup.target = self
        modelPopup.action = #selector(modelChanged)
        contextStrategyPopup.target = self
        contextStrategyPopup.action = #selector(contextStrategyChanged)
        temperatureSlider.target = self
        temperatureSlider.action = #selector(temperatureChanged)
        windowSlider.target = self
        windowSlider.action = #selector(windowChanged)
        apiKeyField.target = self
        apiKeyField.action = #selector(apiKeyEdited)
        apiKeyField.placeholderString = "routerai key"
        saveAPIKeyButton.target = self
        saveAPIKeyButton.action = #selector(saveAPIKeyTapped)
        apiKeyStatusLabel.textColor = .secondaryLabelColor
        apiKeyStatusLabel.lineBreakMode = .byWordWrapping
        apiKeyStatusLabel.maximumNumberOfLines = 2

        let stack = NSStackView(views: [
            makeRow(label: "Model", control: modelPopup),
            makeRow(label: "Context Strategy", control: contextStrategyPopup),
            temperatureLabel,
            temperatureSlider,
            windowLabel,
            windowSlider,
            makeRow(label: "RouterAI API Key", control: apiKeyField),
            saveAPIKeyButton,
            apiKeyStatusLabel
        ])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
        ])
    }

    private func bind() {
        viewModel.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in
                guard let self else { return }
                self.modelPopup.selectItem(withTitle: settings.model.rawValue)
                self.contextStrategyPopup.selectItem(withTitle: settings.contextStrategy.rawValue)
                self.temperatureSlider.doubleValue = settings.temperature
                self.windowSlider.doubleValue = Double(settings.windowSize)
                self.temperatureLabel.stringValue = String(format: "Temperature: %.2f", settings.temperature)
                self.windowLabel.stringValue = "Window: \(settings.windowSize)"
            }
            .store(in: &cancellables)

        viewModel.$apiKey
            .receive(on: DispatchQueue.main)
            .sink { [weak self] apiKey in
                guard let self else { return }
                if self.apiKeyField.stringValue != apiKey {
                    self.apiKeyField.stringValue = apiKey
                }
            }
            .store(in: &cancellables)

        viewModel.$apiKeyStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.apiKeyStatusLabel.stringValue = status
            }
            .store(in: &cancellables)
    }

    private func makeRow(label: String, control: NSView) -> NSView {
        let title = NSTextField(labelWithString: label)
        title.font = .systemFont(ofSize: 12, weight: .medium)

        let row = NSStackView(views: [title, control])
        row.orientation = .horizontal
        row.distribution = .fillProportionally
        row.spacing = 8
        return row
    }

    @objc
    private func modelChanged() {
        guard let title = modelPopup.selectedItem?.title,
              let model = LLMModel(rawValue: title) else { return }
        viewModel.updateModel(model)
    }

    @objc
    private func contextStrategyChanged() {
        guard let title = contextStrategyPopup.selectedItem?.title,
              let strategy = ContextStrategy(rawValue: title) else { return }
        viewModel.updateContextStrategy(strategy)
    }

    @objc
    private func temperatureChanged() {
        viewModel.updateTemperature(temperatureSlider.doubleValue)
    }

    @objc
    private func windowChanged() {
        viewModel.updateWindowSize(Int(windowSlider.intValue))
    }

    @objc
    private func apiKeyEdited() {
        viewModel.updateAPIKey(apiKeyField.stringValue)
    }

    @objc
    private func saveAPIKeyTapped() {
        viewModel.updateAPIKey(apiKeyField.stringValue)
        viewModel.saveAPIKey()
    }
}

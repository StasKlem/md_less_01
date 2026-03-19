import Cocoa
import Combine

final class SettingsViewController: NSViewController {
    private let viewModel: SettingsViewModel
    private var cancellables = Set<AnyCancellable>()

    private let modelPopup = NSPopUpButton()
    private let temperatureSlider = NSSlider(value: 0.4, minValue: 0, maxValue: 1.2, target: nil, action: nil)
    private let temperatureLabel = NSTextField(labelWithString: "Temperature: 0.40")
    private let windowSlider = NSSlider(value: 12, minValue: 4, maxValue: 30, target: nil, action: nil)
    private let windowLabel = NSTextField(labelWithString: "Window: 12")
    private let ragCheckbox = NSButton(checkboxWithTitle: "Enable RAG", target: nil, action: nil)
    private let ragChunkingStrategyPopup = NSPopUpButton()
    private let memoryCheckbox = NSButton(checkboxWithTitle: "Save to memory", target: nil, action: nil)
    private let clearEmbeddingsButton = NSButton(title: "Clear embeddings DB", target: nil, action: nil)
    private let clearEmbeddingsStatusLabel = NSTextField(labelWithString: "")
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
        ragChunkingStrategyPopup.addItems(withTitles: ChunkingStrategyType.allCases.map { $0.rawValue })

        modelPopup.target = self
        modelPopup.action = #selector(modelChanged)
        temperatureSlider.target = self
        temperatureSlider.action = #selector(temperatureChanged)
        windowSlider.target = self
        windowSlider.action = #selector(windowChanged)
        ragCheckbox.target = self
        ragCheckbox.action = #selector(ragToggled)
        ragChunkingStrategyPopup.target = self
        ragChunkingStrategyPopup.action = #selector(ragChunkingStrategyChanged)
        memoryCheckbox.target = self
        memoryCheckbox.action = #selector(memoryToggled)
        apiKeyField.target = self
        apiKeyField.action = #selector(apiKeyEdited)
        apiKeyField.placeholderString = "routerai key"
        saveAPIKeyButton.target = self
        saveAPIKeyButton.action = #selector(saveAPIKeyTapped)
        clearEmbeddingsButton.target = self
        clearEmbeddingsButton.action = #selector(clearEmbeddingsTapped)

        apiKeyStatusLabel.textColor = .secondaryLabelColor
        apiKeyStatusLabel.lineBreakMode = .byWordWrapping
        apiKeyStatusLabel.maximumNumberOfLines = 2
        clearEmbeddingsStatusLabel.textColor = .secondaryLabelColor
        clearEmbeddingsStatusLabel.lineBreakMode = .byWordWrapping
        clearEmbeddingsStatusLabel.maximumNumberOfLines = 2

        let stack = NSStackView(views: [
            makeRow(label: "Model", control: modelPopup),
            temperatureLabel,
            temperatureSlider,
            windowLabel,
            windowSlider,
            ragCheckbox,
            makeRow(label: "RAG chunking", control: ragChunkingStrategyPopup),
            clearEmbeddingsButton,
            clearEmbeddingsStatusLabel,
            memoryCheckbox,
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
                self.temperatureSlider.doubleValue = settings.temperature
                self.windowSlider.doubleValue = Double(settings.windowSize)
                self.temperatureLabel.stringValue = String(format: "Temperature: %.2f", settings.temperature)
                self.windowLabel.stringValue = "Window: \(settings.windowSize)"
                self.ragCheckbox.state = settings.isRAGEnabled ? .on : .off
                self.ragChunkingStrategyPopup.selectItem(withTitle: settings.ragChunkingStrategy.rawValue)
                self.memoryCheckbox.state = settings.isMemoryEnabled ? .on : .off
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

        viewModel.$ragEmbeddingsStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.clearEmbeddingsStatusLabel.stringValue = status
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
    private func temperatureChanged() {
        viewModel.updateTemperature(temperatureSlider.doubleValue)
    }

    @objc
    private func windowChanged() {
        viewModel.updateWindowSize(Int(windowSlider.intValue))
    }

    @objc
    private func ragToggled() {
        viewModel.updateRAGEnabled(ragCheckbox.state == .on)
    }

    @objc
    private func ragChunkingStrategyChanged() {
        guard let title = ragChunkingStrategyPopup.selectedItem?.title,
              let strategy = ChunkingStrategyType(rawValue: title) else { return }
        viewModel.updateRAGChunkingStrategy(strategy)
    }

    @objc
    private func memoryToggled() {
        viewModel.updateMemoryEnabled(memoryCheckbox.state == .on)
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

    @objc
    private func clearEmbeddingsTapped() {
        viewModel.resetRAGEmbeddings()
    }
}

final class InvariantsSettingsViewController: NSViewController {
    private let viewModel: SettingsViewModel
    private var cancellables = Set<AnyCancellable>()

    private let titleLabel = NSTextField(labelWithString: "Planner Invariants (Text)")
    private let invariantsScrollView = NSScrollView()
    private let invariantsTextView = NSTextView()
    private let saveButton = NSButton(title: "Save Invariants", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

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
        view.layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bind()
    }

    private func setupUI() {
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2

        invariantsTextView.isEditable = true
        invariantsTextView.isRichText = false
        invariantsTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        invariantsTextView.isVerticallyResizable = true
        invariantsTextView.isHorizontallyResizable = false
        invariantsTextView.textContainer?.widthTracksTextView = true
        invariantsTextView.textContainerInset = NSSize(width: 8, height: 8)

        invariantsScrollView.borderType = .bezelBorder
        invariantsScrollView.hasVerticalScroller = true
        invariantsScrollView.hasHorizontalScroller = false
        invariantsScrollView.documentView = invariantsTextView

        saveButton.target = self
        saveButton.action = #selector(saveTapped)

        let stack = NSStackView(views: [titleLabel, invariantsScrollView, saveButton, statusLabel])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            invariantsScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])
    }

    private func bind() {
        viewModel.$plannerInvariantsText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self else { return }
                if self.invariantsTextView.string != text {
                    self.invariantsTextView.string = text
                }
            }
            .store(in: &cancellables)

        viewModel.$plannerInvariantsStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.statusLabel.stringValue = text
            }
            .store(in: &cancellables)
    }

    @objc
    private func saveTapped() {
        viewModel.updatePlannerInvariantsText(invariantsTextView.string)
        viewModel.savePlannerInvariants()
    }
}

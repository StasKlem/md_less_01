import Cocoa
import Combine

private final class ChatInputTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "v" {
            paste(nil)
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "v" {
            paste(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func paste(_ sender: Any?) {
        if let plainText = NSPasteboard.general.string(forType: .string) {
            insertText(plainText, replacementRange: selectedRange())
            return
        }
        super.paste(sender)
    }
}

private final class AgentCommandButton: NSButton {
    let command: String

    init(title: String, command: String, target: AnyObject?, action: Selector) {
        self.command = command
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        setButtonType(.momentaryPushIn)
        bezelStyle = .rounded
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class ChatSidebarViewController: NSViewController {
    private enum InputLayout {
        static let visibleLines = 3
        static let textContainerInset = NSSize(width: 6, height: 6)
    }

    private let viewModel: ChatViewModel
    private var cancellables = Set<AnyCancellable>()

    private let dialogHistoryViewController = DialogHistoryViewController(config: .default)
    private let inputTextView = ChatInputTextView()
    private let inputScrollView = NSScrollView()
    private let clearDialogButton = NSButton(title: "Очистить", target: nil, action: nil)
    private let sendButton = NSButton(title: "Отправить", target: nil, action: nil)
    private let approvePlanButton = NSButton(title: "Approve", target: nil, action: nil)
    private let taskAgentsTitleLabel = NSTextField(labelWithString: "Task Agents")
    private let taskAgentsButtonsStack = NSStackView()
    private let controlsTitleLabel = NSTextField(labelWithString: "Agent Controls")
    private let controlsButtonsStack = NSStackView()
    private let plannerStatusLabel = NSTextField(labelWithString: "Планировщик: выключен")
    private var taskAgentLaunchButtons: [TaskAgentID: NSButton] = [:]

    init(viewModel: ChatViewModel) {
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
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bind()
    }

    private func setupUI() {
        clearDialogButton.target = self
        clearDialogButton.action = #selector(clearDialogTapped)
        sendButton.target = self
        sendButton.action = #selector(sendTapped)
        approvePlanButton.target = self
        approvePlanButton.action = #selector(approvePlanTapped)
        approvePlanButton.isEnabled = false
        configureTaskAgentPanel()
        configureInputTextView()

        addChild(dialogHistoryViewController)
        let dialogView = dialogHistoryViewController.view
        dialogView.translatesAutoresizingMaskIntoConstraints = false

        let taskAgentsPanel = NSStackView(views: [taskAgentsTitleLabel, taskAgentsButtonsStack])
        taskAgentsPanel.orientation = .vertical
        taskAgentsPanel.spacing = 4

        let controlsPanel = NSStackView(views: [controlsTitleLabel, controlsButtonsStack])
        controlsPanel.orientation = .vertical
        controlsPanel.spacing = 4

        let inputRow = NSStackView(views: [inputScrollView, clearDialogButton, approvePlanButton, sendButton])
        inputRow.orientation = .horizontal
        inputRow.alignment = .bottom
        inputRow.spacing = 8

        plannerStatusLabel.lineBreakMode = .byTruncatingTail
        plannerStatusLabel.maximumNumberOfLines = 2
        plannerStatusLabel.textColor = .secondaryLabelColor
        plannerStatusLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)

        let root = NSStackView(views: [dialogView, plannerStatusLabel, taskAgentsPanel, controlsPanel, inputRow])
        root.orientation = .vertical
        root.spacing = 8
        root.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            clearDialogButton.widthAnchor.constraint(equalToConstant: 88),
            approvePlanButton.widthAnchor.constraint(equalToConstant: 88),
            sendButton.widthAnchor.constraint(equalToConstant: 88),
            inputScrollView.heightAnchor.constraint(equalToConstant: inputHeightForThreeLines()),
        ])

        rebuildTaskAgentLaunchButtons()
        rebuildControlButtons()
    }

    private func configureInputTextView() {
        inputTextView.isEditable = true
        inputTextView.isSelectable = true
        inputTextView.allowsUndo = true
        inputTextView.isRichText = false
        inputTextView.importsGraphics = false
        inputTextView.isAutomaticQuoteSubstitutionEnabled = false
        inputTextView.isAutomaticTextCompletionEnabled = false
        inputTextView.textContainerInset = InputLayout.textContainerInset
        inputTextView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        inputTextView.isVerticallyResizable = true
        inputTextView.isHorizontallyResizable = false
        inputTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        inputTextView.minSize = .zero
        inputTextView.textContainer?.widthTracksTextView = true
        inputTextView.textContainer?.heightTracksTextView = false
        inputTextView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        inputScrollView.borderType = .bezelBorder
        inputScrollView.hasVerticalScroller = true
        inputScrollView.autohidesScrollers = true
        inputScrollView.hasHorizontalScroller = false
        inputScrollView.drawsBackground = false
        inputScrollView.documentView = inputTextView
    }

    private func configureTaskAgentPanel() {
        taskAgentsTitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        taskAgentsTitleLabel.textColor = .secondaryLabelColor
        controlsTitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        controlsTitleLabel.textColor = .secondaryLabelColor

        taskAgentsButtonsStack.orientation = .horizontal
        taskAgentsButtonsStack.alignment = .leading
        taskAgentsButtonsStack.spacing = 8

        controlsButtonsStack.orientation = .horizontal
        controlsButtonsStack.alignment = .leading
        controlsButtonsStack.spacing = 8
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(inputTextView)
    }

    private func inputHeightForThreeLines() -> CGFloat {
        let font = inputTextView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let lineHeight = inputTextView.layoutManager?.defaultLineHeight(for: font) ?? 17
        return lineHeight * CGFloat(InputLayout.visibleLines) + InputLayout.textContainerInset.height * 2
    }

    private func bind() {
        viewModel.$dialogItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                self?.dialogHistoryViewController.apply(items: items)
            }
            .store(in: &cancellables)

        viewModel.dialogPatchesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] patches in
                self?.dialogHistoryViewController.apply(patches: patches)
            }
            .store(in: &cancellables)

        viewModel.$isSending
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sending in
                self?.sendButton.isEnabled = !sending
                self?.clearDialogButton.isEnabled = !sending
                self?.approvePlanButton.isEnabled = !sending && (self?.viewModel.canApprovePlan ?? false)
                self?.updateTaskAgentLaunchButtons(isEnabled: !sending)
                self?.updateControlButtonsAvailability(isEnabled: !sending)
            }
            .store(in: &cancellables)

        viewModel.$canApprovePlan
            .receive(on: DispatchQueue.main)
            .sink { [weak self] canApprove in
                guard let self else { return }
                self.approvePlanButton.isEnabled = canApprove && !self.viewModel.isSending
            }
            .store(in: &cancellables)

        viewModel.$plannerStepTitle
            .combineLatest(viewModel.$questionnaireProgressText)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] step, progress in
                let stepText = step.map { "Шаг: \($0)." } ?? "Планировщик: выключен."
                let progressText = progress ?? ""
                self?.plannerStatusLabel.stringValue = [stepText, progressText]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            .store(in: &cancellables)

        viewModel.$chatMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildControlButtons()
            }
            .store(in: &cancellables)
    }

    @objc
    private func sendTapped() {
        let text = inputTextView.string
        inputTextView.string = ""
        viewModel.send(text: text)
    }

    @objc
    private func clearDialogTapped() {
        inputTextView.string = ""
        viewModel.clearDialog()
    }

    @objc
    private func approvePlanTapped() {
        viewModel.approvePlan()
    }

    @objc
    private func taskAgentCommandTapped(_ sender: NSButton) {
        guard let commandButton = sender as? AgentCommandButton else { return }
        viewModel.send(text: commandButton.command)
    }

    private func rebuildTaskAgentLaunchButtons() {
        taskAgentLaunchButtons.removeAll()
        taskAgentsButtonsStack.arrangedSubviews.forEach { view in
            taskAgentsButtonsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for descriptor in viewModel.taskAgentCatalog {
            let button = AgentCommandButton(
                title: descriptor.name,
                command: descriptor.startCommand,
                target: self,
                action: #selector(taskAgentCommandTapped)
            )
            taskAgentLaunchButtons[descriptor.id] = button
            taskAgentsButtonsStack.addArrangedSubview(button)
        }
    }

    private func rebuildControlButtons() {
        controlsButtonsStack.arrangedSubviews.forEach { view in
            controlsButtonsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard let descriptor = viewModel.activeTaskAgentDescriptor else { return }
        for control in descriptor.controls {
            let button = AgentCommandButton(
                title: control.title,
                command: control.command,
                target: self,
                action: #selector(taskAgentCommandTapped)
            )
            button.isEnabled = !viewModel.isSending
            controlsButtonsStack.addArrangedSubview(button)
        }
    }

    private func updateTaskAgentLaunchButtons(isEnabled: Bool) {
        for button in taskAgentLaunchButtons.values {
            button.isEnabled = isEnabled
        }
    }

    private func updateControlButtonsAvailability(isEnabled: Bool) {
        for button in controlsButtonsStack.arrangedSubviews.compactMap({ $0 as? NSButton }) {
            button.isEnabled = isEnabled
        }
    }
}

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
    private let sendButton = NSButton(title: "Отправить", target: nil, action: nil)
    private let approvePlanButton = NSButton(title: "Approve", target: nil, action: nil)
    private let startPlannerButton = NSButton(title: "Запустить отпуск", target: nil, action: nil)
    private let plannerStatusLabel = NSTextField(labelWithString: "Планировщик: выключен")

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
        sendButton.target = self
        sendButton.action = #selector(sendTapped)
        approvePlanButton.target = self
        approvePlanButton.action = #selector(approvePlanTapped)
        approvePlanButton.isEnabled = false
        startPlannerButton.target = self
        startPlannerButton.action = #selector(startPlannerTapped)
        configureInputTextView()

        addChild(dialogHistoryViewController)
        let dialogView = dialogHistoryViewController.view
        dialogView.translatesAutoresizingMaskIntoConstraints = false

        let inputRow = NSStackView(views: [inputScrollView, startPlannerButton, approvePlanButton, sendButton])
        inputRow.orientation = .horizontal
        inputRow.alignment = .bottom
        inputRow.spacing = 8

        plannerStatusLabel.lineBreakMode = .byTruncatingTail
        plannerStatusLabel.maximumNumberOfLines = 2
        plannerStatusLabel.textColor = .secondaryLabelColor
        plannerStatusLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)

        let root = NSStackView(views: [dialogView, plannerStatusLabel, inputRow])
        root.orientation = .vertical
        root.spacing = 8
        root.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            startPlannerButton.widthAnchor.constraint(equalToConstant: 120),
            approvePlanButton.widthAnchor.constraint(equalToConstant: 88),
            sendButton.widthAnchor.constraint(equalToConstant: 88),
            inputScrollView.heightAnchor.constraint(equalToConstant: inputHeightForThreeLines()),
        ])
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
                self?.startPlannerButton.isEnabled = !sending
                self?.approvePlanButton.isEnabled = !sending && (self?.viewModel.canApprovePlan ?? false)
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
    }

    @objc
    private func sendTapped() {
        let text = inputTextView.string
        inputTextView.string = ""
        viewModel.send(text: text)
    }

    @objc
    private func startPlannerTapped() {
        viewModel.send(text: "/vacation start")
    }

    @objc
    private func approvePlanTapped() {
        viewModel.approvePlan()
    }
}

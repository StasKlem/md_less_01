import Cocoa

final class ChatSidebarViewController: NSViewController {
    private let historyViewController: DialogHistoryViewController
    private let inputViewController: ChatMessageInputViewController

    init() {
        let historyViewModel = ChatConversationViewModel(
            messages: ChatMessage.previewConversation
        )
        self.historyViewController = DialogHistoryViewController(viewModel: historyViewModel)
        self.inputViewController = ChatMessageInputViewController()
        super.init(nibName: nil, bundle: nil)

        inputViewController.onSend = { [weak historyViewModel] text in
            historyViewModel?.sendUserMessage(text)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = NSView()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
    }

    private func setupLayout() {
        addChild(historyViewController)
        addChild(inputViewController)

        let titleLabel = NSTextField(labelWithString: "Чат")
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.textColor = .labelColor

        let subtitleLabel = NSTextField(labelWithString: "История сообщений и поле для нового сообщения.")
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 0
        subtitleLabel.lineBreakMode = .byWordWrapping

        let headerStack = NSStackView(views: [titleLabel, subtitleLabel])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 4

        let contentStack = NSStackView(views: [historyViewController.view, inputViewController.view])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(headerStack)
        view.addSubview(contentStack)

        headerStack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            headerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            contentStack.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),

            historyViewController.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 260),
            inputViewController.view.heightAnchor.constraint(equalToConstant: 170),

            historyViewController.view.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            inputViewController.view.widthAnchor.constraint(equalTo: contentStack.widthAnchor)
        ])
    }
}

import Cocoa

final class DialogHistoryViewController: NSViewController {
    private let viewModel: ChatConversationViewModel
    private let tableView = NSTableView()

    init(viewModel: ChatConversationViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = NSView()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTableView()
        bindViewModel()
    }

    private func setupTableView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("message"))
        column.title = "Сообщение"
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 64
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.selectionHighlightStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.reloadData()

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = false
        scrollView.documentView = tableView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func bindViewModel() {
        viewModel.onChange = { [weak self] _ in
            DispatchQueue.main.async {
                self?.tableView.reloadData()
                if let count = self?.viewModel.messages.count, count > 0 {
                    self?.tableView.scrollRowToVisible(count - 1)
                }
            }
        }
    }
}

extension DialogHistoryViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        viewModel.messages.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let message = viewModel.messages[row]
        let identifier = NSUserInterfaceItemIdentifier("messageCell")

        let cell: ChatHistoryMessageCellView
        if let existing = tableView.makeView(withIdentifier: identifier, owner: nil) as? ChatHistoryMessageCellView {
            cell = existing
        } else {
            cell = ChatHistoryMessageCellView()
            cell.identifier = identifier
        }

        cell.configure(with: message)
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        let message = viewModel.messages[row]
        let baseHeight: CGFloat = 52
        let additionalLines = max(0, message.text.count / 42)
        return baseHeight + CGFloat(additionalLines * 16)
    }
}

private final class ChatHistoryMessageCellView: NSTableCellView {
    private let authorLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(labelWithString: "")
    private let bubbleView = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with message: ChatMessage) {
        authorLabel.stringValue = message.author.displayName
        messageLabel.stringValue = message.text

        switch message.author {
        case .user:
            bubbleView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
            authorLabel.textColor = .labelColor
        case .assistant:
            bubbleView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            authorLabel.textColor = .labelColor
        case .system:
            bubbleView.layer?.backgroundColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.12).cgColor
            authorLabel.textColor = .secondaryLabelColor
        }
    }

    private func setupLayout() {
        wantsLayer = true

        bubbleView.wantsLayer = true
        bubbleView.layer?.cornerRadius = 12
        bubbleView.layer?.masksToBounds = true
        bubbleView.translatesAutoresizingMaskIntoConstraints = false

        authorLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        authorLabel.translatesAutoresizingMaskIntoConstraints = false

        messageLabel.font = .systemFont(ofSize: 13, weight: .regular)
        messageLabel.textColor = .labelColor
        messageLabel.maximumNumberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [authorLabel, messageLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(bubbleView)
        bubbleView.addSubview(stack)

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            bubbleView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            bubbleView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            bubbleView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),

            stack.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10)
        ])
    }
}

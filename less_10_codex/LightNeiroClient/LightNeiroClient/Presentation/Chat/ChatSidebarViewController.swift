import Cocoa
import Combine

final class ChatSidebarViewController: NSViewController {
    private let viewModel: ChatViewModel
    private var cancellables = Set<AnyCancellable>()

    private let historyTableView = NSTableView()
    private let messagesTableView = NSTableView()
    private let inputField = NSTextField()
    private let sendButton = NSButton(title: "Send", target: nil, action: nil)

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
        let historyScroll = NSScrollView()
        historyScroll.documentView = historyTableView
        historyScroll.hasVerticalScroller = true

        let messagesScroll = NSScrollView()
        messagesScroll.documentView = messagesTableView
        messagesScroll.hasVerticalScroller = true

        historyTableView.headerView = nil
        messagesTableView.headerView = nil

        let historyColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("history"))
        historyColumn.title = "Chats"
        historyTableView.addTableColumn(historyColumn)

        let messageColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("messages"))
        messageColumn.title = "Messages"
        messagesTableView.addTableColumn(messageColumn)

        historyTableView.delegate = self
        historyTableView.dataSource = self
        messagesTableView.delegate = self
        messagesTableView.dataSource = self

        sendButton.target = self
        sendButton.action = #selector(sendTapped)

        let inputRow = NSStackView(views: [inputField, sendButton])
        inputRow.orientation = .horizontal
        inputRow.spacing = 8

        let root = NSStackView(views: [historyScroll, messagesScroll, inputRow])
        root.orientation = .vertical
        root.spacing = 8
        root.translatesAutoresizingMaskIntoConstraints = false

        historyScroll.heightAnchor.constraint(equalToConstant: 130).isActive = true

        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            sendButton.widthAnchor.constraint(equalToConstant: 88),
        ])
    }

    private func bind() {
        viewModel.$historyItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.historyTableView.reloadData() }
            .store(in: &cancellables)

        viewModel.$messageItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.messagesTableView.reloadData()
                let count = self.viewModel.messageItems.count
                if count > 0 {
                    self.messagesTableView.scrollRowToVisible(count - 1)
                }
            }
            .store(in: &cancellables)

        viewModel.$isSending
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sending in
                self?.sendButton.isEnabled = !sending
            }
            .store(in: &cancellables)
    }

    @objc
    private func sendTapped() {
        let text = inputField.stringValue
        inputField.stringValue = ""
        viewModel.send(text: text)
    }
}

extension ChatSidebarViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == historyTableView {
            return viewModel.historyItems.count
        }
        return viewModel.messageItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTextField(labelWithString: "")
        cell.lineBreakMode = .byTruncatingTail

        if tableView == historyTableView {
            let item = viewModel.historyItems[row]
            cell.stringValue = item.isActive ? "• \(item.title)" : item.title
            return cell
        }

        let item = viewModel.messageItems[row]
        cell.stringValue = "[\(item.role.rawValue)] \(item.text)"
        cell.maximumNumberOfLines = 2
        return cell
    }
}

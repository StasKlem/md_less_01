import Cocoa
import Combine

final class ChatSidebarViewController: NSViewController {
    private let viewModel: ChatViewModel
    private var cancellables = Set<AnyCancellable>()

    private let historyTableView = NSTableView()
    private let newBranchButton = NSButton(title: "New Branch", target: nil, action: nil)
    private let dialogHistoryViewController = DialogHistoryViewController(config: .default)
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

        historyTableView.headerView = nil

        let historyColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("history"))
        historyColumn.title = "Chats"
        historyTableView.addTableColumn(historyColumn)

        historyTableView.delegate = self
        historyTableView.dataSource = self

        newBranchButton.target = self
        newBranchButton.action = #selector(createBranchTapped)
        sendButton.target = self
        sendButton.action = #selector(sendTapped)

        addChild(dialogHistoryViewController)
        let dialogView = dialogHistoryViewController.view
        dialogView.translatesAutoresizingMaskIntoConstraints = false

        let inputRow = NSStackView(views: [inputField, sendButton])
        inputRow.orientation = .horizontal
        inputRow.spacing = 8

        let historyHeaderRow = NSStackView(views: [newBranchButton])
        historyHeaderRow.orientation = .horizontal
        historyHeaderRow.alignment = .centerY

        let root = NSStackView(views: [historyHeaderRow, historyScroll, dialogView, inputRow])
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
            .sink { [weak self] items in
                guard let self else { return }
                self.historyTableView.reloadData()
                if let activeIndex = items.firstIndex(where: \.isActive) {
                    self.historyTableView.selectRowIndexes(IndexSet(integer: activeIndex), byExtendingSelection: false)
                }
            }
            .store(in: &cancellables)

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
            }
            .store(in: &cancellables)
    }

    @objc
    private func sendTapped() {
        let text = inputField.stringValue
        inputField.stringValue = ""
        viewModel.send(text: text)
    }

    @objc
    private func createBranchTapped() {
        viewModel.createBranch()
    }
}

extension ChatSidebarViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        viewModel.historyItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTextField(labelWithString: "")
        cell.lineBreakMode = .byTruncatingTail

        let item = viewModel.historyItems[row]
        cell.stringValue = item.isActive ? "• \(item.title)" : item.title
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        viewModel.selectHistoryItem(at: historyTableView.selectedRow)
    }
}

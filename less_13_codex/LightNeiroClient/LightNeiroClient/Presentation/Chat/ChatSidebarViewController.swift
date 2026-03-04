import Cocoa
import Combine

private final class ChatInputTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }

    /// Перехватывает Cmd+V на уровне keyDown, чтобы вставка работала
    /// даже когда событие не проходит через стандартное меню Edit.
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "v" {
            paste(nil)
            return
        }
        super.keyDown(with: event)
    }

    /// Поддерживает системный путь обработки key-equivalent для Cmd+V.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "v" {
            paste(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Вставляет plain text из буфера обмена, чтобы избежать отказа вставки
    /// при несоответствии форматов содержимого pasteboard.
    override func paste(_ sender: Any?) {
        if let plainText = NSPasteboard.general.string(forType: .string) {
            insertText(plainText, replacementRange: selectedRange())
            return
        }
        super.paste(sender)
    }
}

private final class BranchTreeNode {
    let id: UUID
    let title: String
    let isActive: Bool
    let children: [BranchTreeNode]

    init(id: UUID, title: String, isActive: Bool, children: [BranchTreeNode]) {
        self.id = id
        self.title = title
        self.isActive = isActive
        self.children = children
    }
}

private func makeBranchTreeNode(from item: ChatBranchTreeItem) -> BranchTreeNode {
    let children = item.children.map(makeBranchTreeNode(from:))
    return BranchTreeNode(
        id: item.id,
        title: item.title,
        isActive: item.isActive,
        children: children
    )
}

final class ChatSidebarViewController: NSViewController {
    private enum InputLayout {
        static let visibleLines = 3
        static let textContainerInset = NSSize(width: 6, height: 6)
    }

    private let viewModel: ChatViewModel
    private var cancellables = Set<AnyCancellable>()
    private var rootNodes: [BranchTreeNode] = []

    private let branchOutlineView = NSOutlineView()
    private let newBranchButton = NSButton(title: "New Branch", target: nil, action: nil)
    private let dialogHistoryViewController = DialogHistoryViewController(config: .default)
    private let inputTextView = ChatInputTextView()
    private let inputScrollView = NSScrollView()
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
        historyScroll.documentView = branchOutlineView
        historyScroll.hasVerticalScroller = true

        branchOutlineView.headerView = nil

        let historyColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("history"))
        historyColumn.title = "Chats"
        historyColumn.resizingMask = .autoresizingMask
        branchOutlineView.addTableColumn(historyColumn)
        branchOutlineView.outlineTableColumn = historyColumn

        branchOutlineView.delegate = self
        branchOutlineView.dataSource = self
        branchOutlineView.selectionHighlightStyle = .regular

        newBranchButton.target = self
        newBranchButton.action = #selector(createBranchTapped)
        sendButton.target = self
        sendButton.action = #selector(sendTapped)
        configureInputTextView()

        addChild(dialogHistoryViewController)
        let dialogView = dialogHistoryViewController.view
        dialogView.translatesAutoresizingMaskIntoConstraints = false

        let inputRow = NSStackView(views: [inputScrollView, sendButton])
        inputRow.orientation = .horizontal
        inputRow.alignment = .bottom
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
            inputScrollView.heightAnchor.constraint(equalToConstant: inputHeightForThreeLines()),
        ])
    }

    /// Настраивает многострочное поле ввода и контейнер со скроллом.
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
        // Сразу переводим фокус в поле ввода для работы горячих клавиш.
        view.window?.makeFirstResponder(inputTextView)
    }

    /// Возвращает фиксированную высоту поля ввода: ровно 3 строки текста.
    private func inputHeightForThreeLines() -> CGFloat {
        let font = inputTextView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let lineHeight = inputTextView.layoutManager?.defaultLineHeight(for: font) ?? 17
        return lineHeight * CGFloat(InputLayout.visibleLines) + InputLayout.textContainerInset.height * 2
    }

    private func bind() {
        viewModel.$branchTreeItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                guard let self else { return }
                self.rootNodes = items.map(makeBranchTreeNode(from:))
                self.branchOutlineView.reloadData()
                self.expandAllNodes()
                self.selectActiveNode()
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
        let text = inputTextView.string
        inputTextView.string = ""
        viewModel.send(text: text)
    }

    @objc
    private func createBranchTapped() {
        viewModel.createBranch()
    }

    private func expandAllNodes() {
        func expandRecursively(_ node: BranchTreeNode) {
            guard !node.children.isEmpty else { return }
            branchOutlineView.expandItem(node, expandChildren: false)
            node.children.forEach(expandRecursively)
        }
        rootNodes.forEach(expandRecursively)
    }

    private func selectActiveNode() {
        func findActive(in nodes: [BranchTreeNode]) -> BranchTreeNode? {
            for node in nodes {
                if node.isActive {
                    return node
                }
                if let nested = findActive(in: node.children) {
                    return nested
                }
            }
            return nil
        }

        guard let active = findActive(in: rootNodes) else {
            branchOutlineView.deselectAll(nil)
            return
        }

        let row = branchOutlineView.row(forItem: active)
        guard row >= 0 else { return }
        branchOutlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }
}

extension ChatSidebarViewController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? BranchTreeNode else { return rootNodes.count }
        return node.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? BranchTreeNode else { return false }
        return !node.children.isEmpty
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? BranchTreeNode else { return rootNodes[index] }
        return node.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let cell = NSTextField(labelWithString: "")
        cell.lineBreakMode = .byTruncatingTail

        guard let node = item as? BranchTreeNode else { return cell }
        cell.stringValue = node.isActive ? "• \(node.title)" : node.title
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let node = branchOutlineView.item(atRow: branchOutlineView.selectedRow) as? BranchTreeNode else { return }
        viewModel.selectBranch(id: node.id)
    }
}

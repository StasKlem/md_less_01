//
//  ChatView.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import AppKit

/// Вид для отображения истории сообщений чата.
final class ChatView: NSScrollView {
    
    // MARK: - Properties
    
    private let tableView: NSTableView
    private var messages: [Message] = []
    
    private let rowHeight: CGFloat = 24
    
    // MARK: - Callbacks
    
    var onScrollToBottom: (() -> Void)?
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        tableView = NSTableView()
        super.init(frame: frameRect)
        setupTableView()
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    
    private func setupTableView() {
        // Настройка scroll view
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        borderType = .noBorder
        drawsBackground = false
        
        // Настройка table view
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("message")))
        tableView.headerView = nil
        tableView.rowSizeStyle = .custom
        tableView.rowHeight = rowHeight
        tableView.selectionHighlightStyle = .none
        tableView.backgroundColor = .clear
        tableView.translatesAutoresizingMaskIntoConstraints = false
        
        // DataSource & Delegate
        tableView.dataSource = self
        tableView.delegate = self
        
        // Регистрация ячейки
        // NSTableView автоматически создает ячейки через delegate
        
        documentView = tableView
    }
    
    // MARK: - Public Methods
    
    /// Обновить сообщения
    func updateMessages(_ messages: [Message]) {
        self.messages = messages
        
        let rowCount = tableView.numberOfRows
        let newRowCount = messages.count
        
        if newRowCount > rowCount {
            tableView.insertRows(at: IndexSet(integersIn: rowCount..<newRowCount), withAnimation: .slideDown)
        } else if newRowCount < rowCount {
            tableView.removeRows(at: IndexSet(integersIn: newRowCount..<rowCount), withAnimation: .slideUp)
        }
        
        tableView.reloadData()
        
        // Прокрутка вниз
        scrollToBottom()
    }
    
    /// Добавить сообщение
    func appendMessage(_ message: Message) {
        messages.append(message)
        tableView.insertRows(at: [messages.count - 1], withAnimation: .effectFade)
        scrollToBottom()
    }
    
    /// Обновить последнее сообщение
    func updateLastMessage(_ message: Message) {
        guard !messages.isEmpty else { return }
        messages[messages.count - 1] = message
        
        tableView.reloadData(forRowIndexes: IndexSet(integer: messages.count - 1), columnIndexes: IndexSet(integer: 0))
    }
    
    /// Очистить чат
    func clear() {
        messages.removeAll()
        tableView.reloadData()
    }
    
    /// Прокрутка вниз
    func scrollToBottom() {
        guard messages.count > 0 else { return }
        
        DispatchQueue.main.async { [weak self] in
            self?.tableView.scrollRowToVisible(self!.messages.count - 1)
        }
    }
    
    /// Показать индикатор загрузки
    func showLoadingIndicator() {
        // Можно добавить placeholder ячейку
    }
    
    /// Скрыть индикатор загрузки
    func hideLoadingIndicator() {
        // Удалить placeholder ячейку
    }
}

// MARK: - NSTableViewDataSource

extension ChatView: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        messages.count
    }
}

// MARK: - NSTableViewDelegate

extension ChatView: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < messages.count else { return nil }
        
        let message = messages[row]
        
        guard let cellView = tableView.makeView(
            withIdentifier: NSUserInterfaceItemIdentifier("MessageCell"),
            owner: nil
        ) as? MessageCellView else {
            return nil
        }
        
        let maxWidth = tableView.bounds.width - 40
        cellView.configure(with: message, maxWidth: maxWidth)
        
        return cellView
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row < messages.count else { return rowHeight }
        
        let message = messages[row]
        let contentHeight = estimateHeight(for: message)
        
        return max(rowHeight, contentHeight + 16)
    }
    
    private func estimateHeight(for message: Message) -> CGFloat {
        let text = message.content
        let width = tableView.bounds.width - 80
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13)
        ]
        
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: attributes
        )
        
        return rect.height + 16
    }
}

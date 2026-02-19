import Cocoa

// MARK: - Toolbar Manager

final class ToolbarManager: NSObject {
    
    // MARK: - Toolbar Item Identifiers
    
    enum ToolbarItemIdentifier: String {
        case newChat = "NewChat"
        case toggleSettings = "ToggleSettings"
        case about = "About"
    }
    
    // MARK: - Properties
    
    weak var splitViewController: SplitViewController?
    weak var chatViewController: ChatViewController?
    
    private var toolbar: NSToolbar?
    
    // MARK: - Initialization
    
    init(splitViewController: SplitViewController, chatViewController: ChatViewController) {
        self.splitViewController = splitViewController
        self.chatViewController = chatViewController
        super.init()
    }
    
    // MARK: - Setup
    
    func setupToolbar(for window: NSWindow) {
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.showsBaselineSeparator = true
        
        window.toolbar = toolbar
        self.toolbar = toolbar
    }
    
    // MARK: - Actions
    
    @objc private func newChatTapped() {
        chatViewController?.clearChat()
    }
    
    @objc private func toggleSettingsTapped() {
        splitViewController?.toggleSettingsPanel()
    }
    
    @objc private func aboutTapped() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}

// MARK: - NSToolbarDelegate

extension ToolbarManager: NSToolbarDelegate {
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            NSToolbarItem.Identifier(ToolbarItemIdentifier.newChat.rawValue),
            NSToolbarItem.Identifier(ToolbarItemIdentifier.toggleSettings.rawValue),
            NSToolbarItem.Identifier(ToolbarItemIdentifier.about.rawValue),
            .flexibleSpace,
            .space
        ]
    }
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            NSToolbarItem.Identifier(ToolbarItemIdentifier.newChat.rawValue),
            NSToolbarItem.Identifier(ToolbarItemIdentifier.toggleSettings.rawValue),
            .flexibleSpace,
            NSToolbarItem.Identifier(ToolbarItemIdentifier.about.rawValue)
        ]
    }
    
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        
        switch ToolbarItemIdentifier(rawValue: itemIdentifier.rawValue) {
        case .newChat:
            item.label = "Новый чат"
            item.paletteLabel = "Новый чат"
            item.toolTip = "Начать новый чат"
            item.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "Новый чат")
            item.target = self
            item.action = #selector(newChatTapped)
            
        case .toggleSettings:
            item.label = "Настройки"
            item.paletteLabel = "Настройки"
            item.toolTip = "Показать/скрыть панель настроек"
            item.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Настройки")
            item.target = self
            item.action = #selector(toggleSettingsTapped)
            
        case .about:
            item.label = "О приложении"
            item.paletteLabel = "О приложении"
            item.toolTip = "О приложении"
            item.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "О приложении")
            item.target = self
            item.action = #selector(aboutTapped)
            
        case .none:
            break
        }
        
        return item
    }
}

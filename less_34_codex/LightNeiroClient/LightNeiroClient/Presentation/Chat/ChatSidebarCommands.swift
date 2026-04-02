import Foundation

struct ChatSidebarCommand: Equatable {
    let title: String
    let command: String
}

enum ChatSidebarCommandCatalog {
    static let generalCommands: [ChatSidebarCommand] = [
        ChatSidebarCommand(title: "/help", command: "/help")
    ]
}

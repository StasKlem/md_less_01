import Foundation

enum ChatMessageAuthor: String, Sendable, Equatable {
    case user
    case assistant
    case system

    var displayName: String {
        switch self {
        case .user:
            return "Вы"
        case .assistant:
            return "Ассистент"
        case .system:
            return "Система"
        }
    }
}

struct ChatMessage: Identifiable, Sendable, Equatable {
    let id: UUID
    let author: ChatMessageAuthor
    let text: String

    init(id: UUID = UUID(), author: ChatMessageAuthor, text: String) {
        self.id = id
        self.author = author
        self.text = text
    }

    static let previewConversation: [ChatMessage] = [
        ChatMessage(author: .system, text: "Добро пожаловать в чат."),
        ChatMessage(author: .assistant, text: "Введите сообщение внизу, чтобы начать диалог."),
        ChatMessage(author: .user, text: "Покажи историю сообщений."),
        ChatMessage(author: .assistant, text: "История отображается в отдельной панели.")
    ]
}

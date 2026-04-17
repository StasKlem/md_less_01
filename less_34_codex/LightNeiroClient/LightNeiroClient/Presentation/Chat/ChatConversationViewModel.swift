import Foundation

@MainActor
final class ChatConversationViewModel {
    private(set) var messages: [ChatMessage] {
        didSet {
            onChange?(messages)
        }
    }

    var onChange: (([ChatMessage]) -> Void)?

    init(messages: [ChatMessage] = []) {
        self.messages = messages
    }

    func sendUserMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        messages.append(ChatMessage(author: .user, text: trimmed))
    }

    func appendAssistantMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        messages.append(ChatMessage(author: .assistant, text: trimmed))
    }
}

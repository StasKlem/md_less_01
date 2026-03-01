import Combine
import Foundation

struct ChatMessageItem: Equatable {
    let id: UUID
    let role: MessageRole
    let text: String
    let createdAt: Date
}

struct ChatHistoryItem: Equatable {
    let id: UUID
    let title: String
    let isActive: Bool
}

final class ChatViewModel {
    @Published private(set) var historyItems: [ChatHistoryItem] = []
    @Published private(set) var messageItems: [ChatMessageItem] = []
    @Published private(set) var isSending = false

    var onDidSendMessage: (() -> Void)?

    private let sessionID: UUID
    private let branchID: UUID
    private let sendMessageUseCase: SendMessageUseCaseProtocol

    private var currentSettings: LLMSettings = .default

    init(sessionID: UUID, branchID: UUID, sendMessageUseCase: SendMessageUseCaseProtocol) {
        self.sessionID = sessionID
        self.branchID = branchID
        self.sendMessageUseCase = sendMessageUseCase

        historyItems = [
            ChatHistoryItem(id: branchID, title: "main", isActive: true)
        ]
    }

    func apply(settings: LLMSettings) {
        currentSettings = settings
    }

    func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }

        let localUser = ChatMessageItem(id: UUID(), role: .user, text: trimmed, createdAt: Date())
        messageItems.append(localUser)
        isSending = true

        Task { [weak self] in
            guard let self else { return }
            defer { self.isSending = false }

            do {
                let response = try await self.sendMessageUseCase.execute(
                    sessionID: self.sessionID,
                    branchID: self.branchID,
                    userText: trimmed
                )
                let localAssistant = ChatMessageItem(
                    id: response.id,
                    role: .assistant,
                    text: response.content,
                    createdAt: response.createdAt
                )
                self.messageItems.append(localAssistant)
                self.onDidSendMessage?()
            } catch {
                self.messageItems.append(
                    ChatMessageItem(
                        id: UUID(),
                        role: .system,
                        text: "Error: \(error.localizedDescription)",
                        createdAt: Date()
                    )
                )
            }
        }
    }
}

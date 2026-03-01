import Combine
import Foundation

struct ChatHistoryItem: Equatable {
    let id: UUID
    let title: String
    let isActive: Bool
}

@MainActor
final class ChatViewModel {
    @Published private(set) var historyItems: [ChatHistoryItem] = []
    @Published private(set) var dialogItems: [DialogHistoryItemViewState] = []
    @Published private(set) var isSending = false

    var dialogPatchesPublisher: AnyPublisher<[DialogHistoryPatch], Never> {
        dialogPatchesSubject.eraseToAnyPublisher()
    }

    var onDidSendMessage: (() -> Void)?

    private let sessionID: UUID
    private let branchID: UUID
    private let sendMessageUseCase: SendMessageUseCaseProtocol

    private let dialogPatchesSubject = PassthroughSubject<[DialogHistoryPatch], Never>()
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

        let userState = DialogHistoryItemViewState(
            kind: .user,
            text: trimmed,
            status: .sent
        )
        dialogItems.append(userState)

        let assistantID = UUID()
        var assistantState = DialogHistoryItemViewState(
            id: assistantID,
            kind: .assistant,
            text: "",
            status: .streaming
        )
        dialogItems.append(assistantState)

        isSending = true

        Task { [weak self] in
            guard let self else { return }

            do {
                let response = try await self.sendMessageUseCase.execute(
                    sessionID: self.sessionID,
                    branchID: self.branchID,
                    userText: trimmed
                )
                let chunks = self.chunked(response.content, size: 10)
                var streamed = ""
                for chunk in chunks {
                    try await Task.sleep(nanoseconds: 35_000_000)
                    streamed += chunk
                    assistantState = DialogHistoryItemViewState(
                        id: assistantID,
                        kind: .assistant,
                        text: streamed,
                        status: .streaming
                    )
                    self.replaceDialogItem(assistantState)
                    self.dialogPatchesSubject.send([DialogHistoryPatch(id: assistantID, state: assistantState)])
                }

                assistantState = DialogHistoryItemViewState(
                    id: assistantID,
                    kind: .assistant,
                    text: response.content,
                    status: .sent
                )
                self.replaceDialogItem(assistantState)
                self.dialogPatchesSubject.send([DialogHistoryPatch(id: assistantID, state: assistantState)])
                self.onDidSendMessage?()
            } catch {
                let failedAssistant = DialogHistoryItemViewState(
                    id: assistantID,
                    kind: .assistant,
                    text: "Request failed",
                    status: .failed
                )
                self.replaceDialogItem(failedAssistant)
                self.dialogPatchesSubject.send([DialogHistoryPatch(id: assistantID, state: failedAssistant)])

                self.dialogItems.append(
                    DialogHistoryItemViewState(
                        kind: .system,
                        text: "Error: \(error.localizedDescription)",
                        status: .failed
                    )
                )
            }
            self.isSending = false
        }
    }

    private func replaceDialogItem(_ state: DialogHistoryItemViewState) {
        guard let index = dialogItems.firstIndex(where: { $0.id == state.id }) else { return }
        dialogItems[index] = state
    }

    private func chunked(_ text: String, size: Int) -> [String] {
        guard size > 0 else { return [text] }

        var chunks: [String] = []
        var current = ""

        for char in text {
            current.append(char)
            if current.count >= size {
                chunks.append(current)
                current = ""
            }
        }

        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }
}

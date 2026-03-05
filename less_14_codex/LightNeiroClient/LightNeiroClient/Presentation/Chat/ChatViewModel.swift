import Combine
import Foundation

@MainActor
final class ChatViewModel {
    @Published private(set) var dialogItems: [DialogHistoryItemViewState] = []
    @Published private(set) var isSending = false

    var dialogPatchesPublisher: AnyPublisher<[DialogHistoryPatch], Never> {
        dialogPatchesSubject.eraseToAnyPublisher()
    }

    var onDidSendMessage: (() -> Void)?

    private let sessionID: UUID
    private let branchID: UUID
    private let sendMessageUseCase: SendMessageUseCaseProtocol
    private let fetchMessagesUseCase: FetchMessagesUseCaseProtocol

    private let dialogPatchesSubject = PassthroughSubject<[DialogHistoryPatch], Never>()
    private var currentSettings: LLMSettings = .default

    init(
        sessionID: UUID,
        branchID: UUID,
        sendMessageUseCase: SendMessageUseCaseProtocol,
        fetchMessagesUseCase: FetchMessagesUseCaseProtocol
    ) {
        self.sessionID = sessionID
        self.branchID = branchID
        self.sendMessageUseCase = sendMessageUseCase
        self.fetchMessagesUseCase = fetchMessagesUseCase

        Task { [weak self] in
            await self?.loadInitialState()
        }
    }

    func apply(settings: LLMSettings) {
        currentSettings = settings
    }

    func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSending else { return }
        guard !trimmed.isEmpty else { return }

        let userState = DialogHistoryItemViewState(kind: .user, text: trimmed, status: .sent)
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
                    userText: trimmed,
                    assistantInstruction: nil
                )

                assistantState = DialogHistoryItemViewState(
                    id: assistantID,
                    kind: .assistant,
                    text: response.content,
                    status: .sent
                )
                self.replaceDialogItem(assistantState)
                self.dialogPatchesSubject.send([DialogHistoryPatch(id: assistantID, state: assistantState)])

                try await self.loadDialog()
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

    private func loadInitialState() async {
        do {
            try await loadDialog()
        } catch {
            dialogItems = [
                DialogHistoryItemViewState(
                    kind: .system,
                    text: "Failed to load history: \(error.localizedDescription)",
                    status: .failed
                )
            ]
        }
    }

    private func loadDialog() async throws {
        let messages = try await fetchMessagesUseCase.execute(branchID: branchID)
        dialogItems = messages.map { message in
            DialogHistoryItemViewState(
                id: message.id,
                kind: kind(for: message.role),
                text: message.content,
                status: .sent,
                createdAt: message.createdAt
            )
        }
    }

    private func kind(for role: MessageRole) -> DialogMessageKind {
        switch role {
        case .system:
            return .system
        case .user:
            return .user
        case .assistant:
            return .assistant
        }
    }
}

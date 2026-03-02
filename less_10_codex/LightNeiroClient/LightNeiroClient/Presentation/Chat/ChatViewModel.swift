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
    var onActiveBranchChanged: ((UUID) -> Void)?

    private let sessionID: UUID
    private var activeBranchID: UUID
    private let sendMessageUseCase: SendMessageUseCaseProtocol
    private let fetchBranchesUseCase: FetchBranchesUseCaseProtocol
    private let fetchMessagesUseCase: FetchMessagesUseCaseProtocol
    private let cloneDialogToBranchUseCase: CloneDialogToBranchUseCaseProtocol
    private let switchBranchUseCase: SwitchBranchUseCaseProtocol
    private let createBranchUseCase: CreateBranchUseCaseProtocol
    private let addBranchCreatedSystemMessageUseCase: AddBranchCreatedSystemMessageUseCaseProtocol

    private let dialogPatchesSubject = PassthroughSubject<[DialogHistoryPatch], Never>()
    private var currentSettings: LLMSettings = .default

    init(
        sessionID: UUID,
        branchID: UUID,
        sendMessageUseCase: SendMessageUseCaseProtocol,
        fetchBranchesUseCase: FetchBranchesUseCaseProtocol,
        fetchMessagesUseCase: FetchMessagesUseCaseProtocol,
        cloneDialogToBranchUseCase: CloneDialogToBranchUseCaseProtocol,
        switchBranchUseCase: SwitchBranchUseCaseProtocol,
        createBranchUseCase: CreateBranchUseCaseProtocol,
        addBranchCreatedSystemMessageUseCase: AddBranchCreatedSystemMessageUseCaseProtocol
    ) {
        self.sessionID = sessionID
        self.activeBranchID = branchID
        self.sendMessageUseCase = sendMessageUseCase
        self.fetchBranchesUseCase = fetchBranchesUseCase
        self.fetchMessagesUseCase = fetchMessagesUseCase
        self.cloneDialogToBranchUseCase = cloneDialogToBranchUseCase
        self.switchBranchUseCase = switchBranchUseCase
        self.createBranchUseCase = createBranchUseCase
        self.addBranchCreatedSystemMessageUseCase = addBranchCreatedSystemMessageUseCase

        Task { [weak self] in
            await self?.loadInitialState()
        }
    }

    func apply(settings: LLMSettings) {
        currentSettings = settings
    }

    func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        let targetBranchID = activeBranchID

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
                    branchID: targetBranchID,
                    userText: trimmed
                )
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

    func selectHistoryItem(at index: Int) {
        guard !isSending else { return }
        guard historyItems.indices.contains(index) else { return }
        let selected = historyItems[index]
        guard selected.id != activeBranchID else { return }

        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.switchBranchUseCase.execute(
                    sessionID: self.sessionID,
                    targetBranchID: selected.id
                )
                self.activeBranchID = selected.id
                self.onActiveBranchChanged?(selected.id)
                try await self.refreshHistoryItems()
                try await self.loadDialog(for: selected.id)
            } catch {
                self.dialogItems.append(
                    DialogHistoryItemViewState(
                        kind: .system,
                        text: "Failed to switch branch: \(error.localizedDescription)",
                        status: .failed
                    )
                )
            }
        }
    }

    func createBranch() {
        guard !isSending else { return }
        let nextName = nextBranchName()
        let sourceBranchID = activeBranchID

        Task { [weak self] in
            guard let self else { return }
            do {
                let sourceBranchName = try await self.resolveBranchName(branchID: sourceBranchID)
                let branch = try await self.createBranchUseCase.execute(
                    sessionID: self.sessionID,
                    parentCheckpointID: nil,
                    name: nextName
                )
                try await self.cloneDialogToBranchUseCase.execute(
                    sourceBranchID: sourceBranchID,
                    targetBranchID: branch.id
                )
                _ = try await self.switchBranchUseCase.execute(
                    sessionID: self.sessionID,
                    targetBranchID: branch.id
                )
                try await self.addBranchCreatedSystemMessageUseCase.execute(
                    branchID: branch.id,
                    sourceBranchName: sourceBranchName
                )
                self.activeBranchID = branch.id
                self.onActiveBranchChanged?(branch.id)
                try await self.refreshHistoryItems()
                try await self.loadDialog(for: branch.id)
            } catch {
                self.dialogItems.append(
                    DialogHistoryItemViewState(
                        kind: .system,
                        text: "Failed to create branch: \(error.localizedDescription)",
                        status: .failed
                    )
                )
            }
        }
    }

    private func replaceDialogItem(_ state: DialogHistoryItemViewState) {
        guard let index = dialogItems.firstIndex(where: { $0.id == state.id }) else { return }
        dialogItems[index] = state
    }

    private func loadInitialState() async {
        do {
            try await refreshHistoryItems()
            try await loadDialog(for: activeBranchID)
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

    private func refreshHistoryItems() async throws {
        let branches = try await fetchBranchesUseCase.execute(sessionID: sessionID)
        historyItems = branches.map {
            ChatHistoryItem(id: $0.id, title: $0.name, isActive: $0.id == activeBranchID)
        }
    }

    private func loadDialog(for branchID: UUID) async throws {
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

    private func nextBranchName() -> String {
        let prefix = "branch-"
        let indices = historyItems.compactMap { item -> Int? in
            guard item.title.hasPrefix(prefix) else { return nil }
            return Int(item.title.dropFirst(prefix.count))
        }
        return "\(prefix)\((indices.max() ?? 0) + 1)"
    }

    private func resolveBranchName(branchID: UUID) async throws -> String {
        let branches = try await fetchBranchesUseCase.execute(sessionID: sessionID)
        return branches.first(where: { $0.id == branchID })?.name ?? "unknown"
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

import Combine
import Foundation

/// Элемент списка веток в боковой истории чатов.
struct ChatHistoryItem: Equatable {
    let id: UUID
    let title: String
    let isActive: Bool
}

@MainActor
/// ViewModel чата: история веток, сообщения активной ветки и действия пользователя.
final class ChatViewModel {
    @Published private(set) var historyItems: [ChatHistoryItem] = []
    @Published private(set) var dialogItems: [DialogHistoryItemViewState] = []
    @Published private(set) var isSending = false

    /// Паблишер точечных патчей для частичного обновления ячеек диалога.
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

    /// Создаёт ViewModel чата и загружает начальное состояние.
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

    /// Применяет актуальные настройки, пришедшие из SettingsViewModel.
    func apply(settings: LLMSettings) {
        currentSettings = settings
    }

    /// Отправляет пользовательский текст в активную ветку.
    func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        // Фиксируем ветку на момент отправки: если пользователь быстро переключится,
        // ответ и метрики все равно сохранятся в исходную ветку.
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
                try await self.loadDialog(for: targetBranchID)
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

    /// Переключает активную ветку по индексу выбранной строки в истории.
    func selectHistoryItem(at index: Int) {
        guard !isSending else { return }
        guard historyItems.indices.contains(index) else { return }
        let selected = historyItems[index]
        guard selected.id != activeBranchID else { return }

        Task { [weak self] in
            guard let self else { return }
            do {
                // Доменное переключение: обновляем activeBranchID у сессии в репозитории.
                _ = try await self.switchBranchUseCase.execute(
                    sessionID: self.sessionID,
                    targetBranchID: selected.id
                )
                self.activeBranchID = selected.id
                // Нотификация нужна, чтобы Settings/SessionInfo переключились на ту же ветку.
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

    /// Создаёт новую ветку, клонирует в неё текущий диалог и переключается на неё.
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
                // Новая ветка стартует с копией текущего диалога, чтобы можно было продолжить
                // обсуждение от текущего контекста, не теряя уже набранную историю.
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
                // После создания ветки синхронизируем все панели так же, как и при обычном switch.
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

    /// Заменяет временное состояние сообщения (например, streaming -> sent/failed).
    private func replaceDialogItem(_ state: DialogHistoryItemViewState) {
        guard let index = dialogItems.firstIndex(where: { $0.id == state.id }) else { return }
        dialogItems[index] = state
    }

    /// Загружает список веток и сообщения для стартовой активной ветки.
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

    /// Перечитывает ветки сессии и обновляет индикатор активной ветки.
    private func refreshHistoryItems() async throws {
        let branches = try await fetchBranchesUseCase.execute(sessionID: sessionID)
        historyItems = branches.map {
            ChatHistoryItem(id: $0.id, title: $0.name, isActive: $0.id == activeBranchID)
        }
    }

    /// Загружает все сообщения выбранной ветки и маппит их в view state.
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

    /// Генерирует следующее имя ветки в формате `branch-N`.
    private func nextBranchName() -> String {
        let prefix = "branch-"
        let indices = historyItems.compactMap { item -> Int? in
            guard item.title.hasPrefix(prefix) else { return nil }
            return Int(item.title.dropFirst(prefix.count))
        }
        return "\(prefix)\((indices.max() ?? 0) + 1)"
    }

    /// Возвращает отображаемое имя ветки по идентификатору.
    private func resolveBranchName(branchID: UUID) async throws -> String {
        let branches = try await fetchBranchesUseCase.execute(sessionID: sessionID)
        return branches.first(where: { $0.id == branchID })?.name ?? "unknown"
    }

    /// Преобразует доменную роль сообщения в UI-тип ячейки.
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

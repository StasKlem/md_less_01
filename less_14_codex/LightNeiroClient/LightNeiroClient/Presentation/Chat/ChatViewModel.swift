import Combine
import Foundation

@MainActor
final class ChatViewModel {
    enum ChatMode: Equatable {
        case `default`
        case vacationPlanner
    }

    @Published private(set) var dialogItems: [DialogHistoryItemViewState] = []
    @Published private(set) var isSending = false
    @Published private(set) var chatMode: ChatMode = .default
    @Published private(set) var plannerStepTitle: String?

    var dialogPatchesPublisher: AnyPublisher<[DialogHistoryPatch], Never> {
        dialogPatchesSubject.eraseToAnyPublisher()
    }

    var onDidSendMessage: (() -> Void)?

    private let session: ChatSession
    private let sendMessageUseCase: SendMessageUseCaseProtocol
    private let fetchMessagesUseCase: FetchMessagesUseCaseProtocol
    private let startVacationPlanningUseCase: StartVacationPlanningUseCaseProtocol?
    private let handleVacationPlanningEventUseCase: HandleVacationPlanningEventUseCaseProtocol?
    private let getVacationPlanningStatusUseCase: GetVacationPlanningStatusUseCaseProtocol?

    private let dialogPatchesSubject = PassthroughSubject<[DialogHistoryPatch], Never>()
    private var currentSettings: LLMSettings = .default
    private var lastPlannerState: VacationPlanningState?

    init(
        session: ChatSession,
        sendMessageUseCase: SendMessageUseCaseProtocol,
        fetchMessagesUseCase: FetchMessagesUseCaseProtocol,
        startVacationPlanningUseCase: StartVacationPlanningUseCaseProtocol? = nil,
        handleVacationPlanningEventUseCase: HandleVacationPlanningEventUseCaseProtocol? = nil,
        getVacationPlanningStatusUseCase: GetVacationPlanningStatusUseCaseProtocol? = nil
    ) {
        self.session = session
        self.sendMessageUseCase = sendMessageUseCase
        self.fetchMessagesUseCase = fetchMessagesUseCase
        self.startVacationPlanningUseCase = startVacationPlanningUseCase
        self.handleVacationPlanningEventUseCase = handleVacationPlanningEventUseCase
        self.getVacationPlanningStatusUseCase = getVacationPlanningStatusUseCase

        Task { [weak self] in
            await self?.loadInitialState()
            await self?.loadPlannerStatusIfExists()
        }
    }

    func apply(settings: LLMSettings) {
        currentSettings = settings
    }

    func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSending else { return }
        guard !trimmed.isEmpty else { return }
        if handlePlannerCommand(text: trimmed) {
            return
        }

        if chatMode == .vacationPlanner {
            sendToVacationPlanner(text: trimmed)
            return
        }

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
                    sessionID: self.session.id,
                    branchID: self.session.activeBranchID,
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
                    text: "Запрос не выполнен",
                    status: .failed
                )
                self.replaceDialogItem(failedAssistant)
                self.dialogPatchesSubject.send([DialogHistoryPatch(id: assistantID, state: failedAssistant)])

                self.dialogItems.append(
                    DialogHistoryItemViewState(
                        kind: .system,
                        text: "Ошибка: \(error.localizedDescription)",
                        status: .failed
                    )
                )
            }
            self.isSending = false
        }
    }

    private func handlePlannerCommand(text: String) -> Bool {
        let command = text.lowercased()
        guard command.hasPrefix("/vacation") else { return false }

        if command == "/vacation stop" {
            chatMode = .default
            plannerStepTitle = nil
            appendSystemMessage("Планировщик отпуска отключен.")
            return true
        }

        if command == "/vacation start" || command == "/vacation" {
            startVacationPlanner()
            return true
        }

        appendSystemMessage("Неизвестная команда планировщика. Используйте `/vacation start` или `/vacation stop`.")
        return true
    }

    private func startVacationPlanner() {
        guard let useCase = startVacationPlanningUseCase else {
            appendSystemMessage("Планировщик отпуска недоступен в этой сборке.")
            return
        }
        guard !isSending else { return }
        isSending = true
        chatMode = .vacationPlanner

        Task { [weak self] in
            guard let self else { return }
            defer { self.isSending = false }
            do {
                let result = try await useCase.execute(
                    sessionID: self.session.id,
                    branchID: self.session.activeBranchID
                )
                self.applyPlannerResult(result)
            } catch {
                self.appendSystemMessage("Не удалось запустить планировщик отпуска: \(error.localizedDescription)")
            }
        }
    }

    private func sendToVacationPlanner(text: String) {
        guard let useCase = handleVacationPlanningEventUseCase else {
            appendSystemMessage("Обработчик планировщика отпуска недоступен.")
            return
        }

        dialogItems.append(DialogHistoryItemViewState(kind: .user, text: text, status: .sent))
        isSending = true

        Task { [weak self] in
            guard let self else { return }
            defer { self.isSending = false }
            do {
                let result = try await useCase.execute(
                    sessionID: self.session.id,
                    branchID: self.session.activeBranchID,
                    userText: text
                )
                self.applyPlannerResult(result)
                self.onDidSendMessage?()
            } catch {
                self.appendSystemMessage("Ошибка планировщика отпуска: \(error.localizedDescription)")
            }
        }
    }

    private func applyPlannerResult(_ result: VacationPlanningTurnResult) {
        plannerStepTitle = result.snapshot.state.title
        if lastPlannerState != result.snapshot.state {
            appendSystemMessage(
                "Состояние планировщика изменилось: \(result.snapshot.state.title)",
                tone: .stateTransition
            )
        }
        lastPlannerState = result.snapshot.state
        if case let .failed(reason) = result.snapshot.state {
            appendSystemMessage("Ошибка инварианта/перехода планировщика: \(reason)")
        }
        for message in result.agentMessages {
            dialogItems.append(DialogHistoryItemViewState(kind: .assistant, text: message, status: .sent))
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
                    text: "Не удалось загрузить историю: \(error.localizedDescription)",
                    status: .failed
                )
            ]
        }
    }

    private func loadPlannerStatusIfExists() async {
        guard let useCase = getVacationPlanningStatusUseCase else { return }
        do {
            let snapshot = try await useCase.execute(
                sessionID: session.id,
                branchID: session.activeBranchID
            )
            plannerStepTitle = snapshot.state.title
            lastPlannerState = snapshot.state
            if snapshot.state != .idle {
                chatMode = .vacationPlanner
            }
        } catch {
            appendSystemMessage("Не удалось загрузить состояние планировщика: \(error.localizedDescription)")
        }
    }

    private func loadDialog() async throws {
        let messages = try await fetchMessagesUseCase.execute(branchID: session.activeBranchID)
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

    private func appendSystemMessage(_ text: String, tone: DialogMessageTone = .normal) {
        dialogItems.append(
            DialogHistoryItemViewState(
                kind: .system,
                text: text,
                status: .sent,
                tone: tone
            )
        )
    }
}

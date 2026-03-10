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
    @Published private(set) var questionnaireState: QuestionnaireState = .empty
    @Published private(set) var questionnaireProgressText: String?

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
            sendToVacationPlanner(text: trimmed, source: .chat)
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

    func submitQuestionnaireForm(values: [String: QuestionnaireValue]) {
        guard chatMode == .vacationPlanner else { return }
        let payload = FormSubmissionPayload(
            fields: values.map { key, value in
                FormSubmissionField(fieldID: key, value: value)
            }
        )
        guard
            let data = try? JSONEncoder().encode(payload),
            let json = String(data: data, encoding: .utf8)
        else {
            appendSystemMessage("Не удалось сериализовать данные формы.")
            return
        }
        sendToVacationPlanner(text: json, source: .form)
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

    private func sendToVacationPlanner(text: String, source: QuestionnaireAnswerSource) {
        guard let useCase = handleVacationPlanningEventUseCase else {
            appendSystemMessage("Обработчик планировщика отпуска недоступен.")
            return
        }

        if lastPlannerState == .destinationRequest {
            appendSystemMessage(
                stateListMessage(current: .validatingDestination),
                tone: .stateTransition
            )
            lastPlannerState = .validatingDestination
            plannerStepTitle = VacationPlanningState.validatingDestination.title
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
                    userText: text,
                    source: source
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
        questionnaireState = result.snapshot.context.questionnaireState
        questionnaireProgressText = progressText(for: result.snapshot.context.questionnaireState)
        if lastPlannerState != result.snapshot.state {
            appendSystemMessage(
                stateListMessage(current: result.snapshot.state),
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
            questionnaireState = snapshot.context.questionnaireState
            questionnaireProgressText = progressText(for: snapshot.context.questionnaireState)
            if snapshot.state != .idle {
                chatMode = .vacationPlanner
                appendSystemMessage(resumeHint(for: snapshot))
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

    private func progressText(for state: QuestionnaireState) -> String {
        if state.missingHard.isEmpty, state.missingSoft.isEmpty {
            return "Анкета: hard complete, soft complete."
        }
        if state.missingHard.isEmpty {
            return "Анкета: hard complete, soft missing: \(state.missingSoft.joined(separator: ", "))."
        }
        return "Анкета: hard missing: \(state.missingHard.joined(separator: ", "))."
    }

    private func stateListMessage(current: VacationPlanningState) -> String {
        let ordered: [VacationPlanningState] = [
            .idle,
            .destinationRequest,
            .validatingDestination,
            .awaitingPlanApproval,
            .generateResult,
        ]

        var lines: [String] = ["Состояния агента (текущее отмечено [x]):"]
        for state in ordered {
            let marker = (state == current) ? "[x]" : "[ ]"
            lines.append("\(marker) \(state.title)")
        }

        if case let .failed(reason) = current {
            lines.append("[x] Ошибка: \(reason)")
        }

        return lines.joined(separator: "\n")
    }

    private func resumeHint(for snapshot: VacationPlanningSnapshot) -> String {
        let action: String
        switch snapshot.state {
        case .destinationRequest:
            action = "Укажите место назначения."
        case .validatingDestination:
            action = "Проверяется ответ по месту назначения."
        case .awaitingPlanApproval:
            action = "Ожидается команда `approve` или `revise: ...`."
        case .generateResult:
            action = "Генерируется итоговый план отдыха."
        case .failed:
            action = "Отправьте `revise: ...`, чтобы продолжить."
        default:
            action = "Агент не активен."
        }
        return "Возобновлен планировщик: \(snapshot.state.title). \(action)"
    }
}

private struct FormSubmissionPayload: Encodable {
    let fields: [FormSubmissionField]
}

private struct FormSubmissionField: Encodable {
    let fieldID: String
    let value: QuestionnaireValue
}

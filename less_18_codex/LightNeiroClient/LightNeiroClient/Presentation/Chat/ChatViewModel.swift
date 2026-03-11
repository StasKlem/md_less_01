import Combine
import Foundation

@MainActor
final class ChatViewModel {
    enum ChatMode: Equatable {
        case `default`
        case vacationPlanner
        case mockTaskAgent
        case counterTaskAgent
    }

    @Published private(set) var dialogItems: [DialogHistoryItemViewState] = []
    @Published private(set) var isSending = false
    @Published private(set) var chatMode: ChatMode = .default
    @Published private(set) var plannerStepTitle: String?
    @Published private(set) var canApprovePlan = false
    @Published private(set) var questionnaireState: QuestionnaireState = .empty
    @Published private(set) var questionnaireProgressText: String?

    let taskAgentCatalog: [TaskAgentDescriptor]

    var activeTaskAgentDescriptor: TaskAgentDescriptor? {
        guard let activeID = activeTaskAgentID else { return nil }
        return taskAgentCatalog.first(where: { $0.id == activeID })
    }

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
    private let fetchVacationPlannerMCPToolsUseCase: FetchVacationPlannerMCPToolsUseCaseProtocol?
    private let startMockTaskAgentUseCase: StartMockTaskAgentUseCaseProtocol?
    private let handleMockTaskAgentEventUseCase: HandleMockTaskAgentEventUseCaseProtocol?
    private let getMockTaskAgentStatusUseCase: GetMockTaskAgentStatusUseCaseProtocol?
    private let startCounterTaskAgentUseCase: StartCounterTaskAgentUseCaseProtocol?
    private let stopCounterTaskAgentUseCase: StopCounterTaskAgentUseCaseProtocol?
    private let configureCounterTaskAgentIntervalUseCase: ConfigureCounterTaskAgentIntervalUseCaseProtocol?
    private let tickCounterTaskAgentUseCase: TickCounterTaskAgentUseCaseProtocol?
    private let getCounterTaskAgentStatusUseCase: GetCounterTaskAgentStatusUseCaseProtocol?

    private let dialogPatchesSubject = PassthroughSubject<[DialogHistoryPatch], Never>()
    private var currentSettings: LLMSettings = .default
    private var lastPlannerState: VacationPlanningState?
    private var lastMockTaskAgentState: MockTaskAgentState?
    private var lastCounterTaskAgentState: CounterTaskAgentState?
    private var counterTimerTask: Task<Void, Never>?
    private var isCounterTickInFlight = false

    init(
        session: ChatSession,
        sendMessageUseCase: SendMessageUseCaseProtocol,
        fetchMessagesUseCase: FetchMessagesUseCaseProtocol,
        startVacationPlanningUseCase: StartVacationPlanningUseCaseProtocol? = nil,
        handleVacationPlanningEventUseCase: HandleVacationPlanningEventUseCaseProtocol? = nil,
        getVacationPlanningStatusUseCase: GetVacationPlanningStatusUseCaseProtocol? = nil,
        fetchVacationPlannerMCPToolsUseCase: FetchVacationPlannerMCPToolsUseCaseProtocol? = nil,
        startMockTaskAgentUseCase: StartMockTaskAgentUseCaseProtocol? = nil,
        handleMockTaskAgentEventUseCase: HandleMockTaskAgentEventUseCaseProtocol? = nil,
        getMockTaskAgentStatusUseCase: GetMockTaskAgentStatusUseCaseProtocol? = nil,
        startCounterTaskAgentUseCase: StartCounterTaskAgentUseCaseProtocol? = nil,
        stopCounterTaskAgentUseCase: StopCounterTaskAgentUseCaseProtocol? = nil,
        configureCounterTaskAgentIntervalUseCase: ConfigureCounterTaskAgentIntervalUseCaseProtocol? = nil,
        tickCounterTaskAgentUseCase: TickCounterTaskAgentUseCaseProtocol? = nil,
        getCounterTaskAgentStatusUseCase: GetCounterTaskAgentStatusUseCaseProtocol? = nil,
        taskAgentCatalog: [TaskAgentDescriptor] = TaskAgentCatalog.all
    ) {
        self.session = session
        self.sendMessageUseCase = sendMessageUseCase
        self.fetchMessagesUseCase = fetchMessagesUseCase
        self.startVacationPlanningUseCase = startVacationPlanningUseCase
        self.handleVacationPlanningEventUseCase = handleVacationPlanningEventUseCase
        self.getVacationPlanningStatusUseCase = getVacationPlanningStatusUseCase
        self.fetchVacationPlannerMCPToolsUseCase = fetchVacationPlannerMCPToolsUseCase
        self.startMockTaskAgentUseCase = startMockTaskAgentUseCase
        self.handleMockTaskAgentEventUseCase = handleMockTaskAgentEventUseCase
        self.getMockTaskAgentStatusUseCase = getMockTaskAgentStatusUseCase
        self.startCounterTaskAgentUseCase = startCounterTaskAgentUseCase
        self.stopCounterTaskAgentUseCase = stopCounterTaskAgentUseCase
        self.configureCounterTaskAgentIntervalUseCase = configureCounterTaskAgentIntervalUseCase
        self.tickCounterTaskAgentUseCase = tickCounterTaskAgentUseCase
        self.getCounterTaskAgentStatusUseCase = getCounterTaskAgentStatusUseCase
        self.taskAgentCatalog = taskAgentCatalog

        Task { [weak self] in
            await self?.loadInitialState()
            await self?.loadPlannerStatusIfExists()
        }
    }

    deinit {
        counterTimerTask?.cancel()
    }

    func apply(settings: LLMSettings) {
        currentSettings = settings
    }

    func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSending else { return }
        guard !trimmed.isEmpty else { return }
        if handleAgentCommand(text: trimmed) {
            return
        }

        if chatMode == .vacationPlanner {
            sendToVacationPlanner(text: trimmed, source: .chat)
            return
        }
        if chatMode == .mockTaskAgent {
            sendToMockTaskAgent(text: trimmed)
            return
        }
        if chatMode == .counterTaskAgent {
            appendSystemMessage("Counter Task Agent работает в фоне. Используйте `/counter interval <сек>` или `/counter stop`.")
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

    func approvePlan() {
        guard chatMode == .vacationPlanner, lastPlannerState == .awaitingPlanApproval else { return }
        send(text: "approve")
    }

    private func handleAgentCommand(text: String) -> Bool {
        let command = text.lowercased()
        if command.hasPrefix("/vacation") {
            return handleVacationCommand(command)
        }
        if command.hasPrefix("/task") {
            return handleMockTaskAgentCommand(command)
        }
        if command.hasPrefix("/counter") {
            return handleCounterTaskAgentCommand(command)
        }
        return false
    }

    private func handleVacationCommand(_ command: String) -> Bool {
        if command == "/vacation stop" {
            stopCounterTimer()
            chatMode = .default
            plannerStepTitle = nil
            updateApproveAvailability()
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

    private func handleMockTaskAgentCommand(_ command: String) -> Bool {
        if command == "/task stop" {
            stopCounterTimer()
            chatMode = .default
            plannerStepTitle = nil
            questionnaireProgressText = nil
            appendSystemMessage("Mock Task Agent отключен.")
            return true
        }

        if command == "/task start" || command == "/task" {
            startMockTaskAgent()
            return true
        }

        appendSystemMessage("Неизвестная команда task-агента. Используйте `/task start` или `/task stop`.")
        return true
    }

    private func handleCounterTaskAgentCommand(_ command: String) -> Bool {
        if command == "/counter stop" {
            stopCounterTaskAgent()
            return true
        }

        if command == "/counter" || command == "/counter start" {
            startCounterTaskAgent(intervalSeconds: nil)
            return true
        }

        if command.hasPrefix("/counter start ") {
            guard let value = parseIntervalSeconds(from: command.replacingOccurrences(of: "/counter start ", with: "")) else {
                appendSystemMessage("Некорректный интервал. Пример: `/counter start 5`.")
                return true
            }
            startCounterTaskAgent(intervalSeconds: value)
            return true
        }

        if command.hasPrefix("/counter interval ") {
            guard let value = parseIntervalSeconds(from: command.replacingOccurrences(of: "/counter interval ", with: "")) else {
                appendSystemMessage("Некорректный интервал. Пример: `/counter interval 2.5`.")
                return true
            }
            configureCounterTaskAgentInterval(value)
            return true
        }

        appendSystemMessage("Неизвестная команда counter-агента. Используйте `/counter start [сек]`, `/counter interval <сек>` или `/counter stop`.")
        return true
    }

    private func startVacationPlanner() {
        stopCounterTimer()
        guard let useCase = startVacationPlanningUseCase else {
            appendSystemMessage("Планировщик отпуска недоступен в этой сборке.")
            return
        }
        guard !isSending else { return }
        isSending = true
        chatMode = .vacationPlanner
        updateApproveAvailability()

        Task { [weak self] in
            guard let self else { return }
            defer { self.isSending = false }
            do {
                if let mcpToolsUseCase = self.fetchVacationPlannerMCPToolsUseCase {
                    let mcpToolsMessage = await mcpToolsUseCase.execute()
                    self.appendSystemMessage(mcpToolsMessage)
                }
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

    private func startMockTaskAgent() {
        stopCounterTimer()
        guard let useCase = startMockTaskAgentUseCase else {
            appendSystemMessage("Mock Task Agent недоступен в этой сборке.")
            return
        }
        guard !isSending else { return }
        isSending = true
        chatMode = .mockTaskAgent
        questionnaireState = .empty
        questionnaireProgressText = nil
        updateApproveAvailability()

        Task { [weak self] in
            guard let self else { return }
            defer { self.isSending = false }
            do {
                let result = try await useCase.execute(
                    sessionID: self.session.id,
                    branchID: self.session.activeBranchID
                )
                self.applyMockTaskAgentResult(result)
            } catch {
                self.appendSystemMessage("Не удалось запустить Mock Task Agent: \(error.localizedDescription)")
            }
        }
    }

    private func sendToMockTaskAgent(text: String) {
        guard let useCase = handleMockTaskAgentEventUseCase else {
            appendSystemMessage("Обработчик Mock Task Agent недоступен.")
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
                self.applyMockTaskAgentResult(result)
                self.onDidSendMessage?()
            } catch {
                self.appendSystemMessage("Ошибка Mock Task Agent: \(error.localizedDescription)")
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
        updateApproveAvailability()
        if case let .failed(reason) = result.snapshot.state {
            appendSystemMessage("Ошибка инварианта/перехода планировщика: \(reason)")
        }
        for message in result.agentMessages {
            dialogItems.append(DialogHistoryItemViewState(kind: .assistant, text: message, status: .sent))
        }
    }

    private func applyMockTaskAgentResult(_ result: MockTaskAgentTurnResult) {
        plannerStepTitle = result.snapshot.state.title
        questionnaireState = .empty
        questionnaireProgressText = mockTaskAgentProgressText(for: result.snapshot)
        if lastMockTaskAgentState != result.snapshot.state {
            appendSystemMessage(
                mockTaskAgentStateListMessage(current: result.snapshot.state),
                tone: .stateTransition
            )
        }
        lastMockTaskAgentState = result.snapshot.state
        updateApproveAvailability()
        if case let .failed(reason) = result.snapshot.state {
            appendSystemMessage("Ошибка mock task-агента: \(reason)")
        }
        for message in result.agentMessages {
            dialogItems.append(DialogHistoryItemViewState(kind: .assistant, text: message, status: .sent))
        }
    }

    private func startCounterTaskAgent(intervalSeconds: TimeInterval?) {
        stopCounterTimer()
        guard let useCase = startCounterTaskAgentUseCase else {
            appendSystemMessage("Counter Task Agent недоступен в этой сборке.")
            return
        }
        guard !isSending else { return }
        isSending = true
        chatMode = .counterTaskAgent
        questionnaireState = .empty
        updateApproveAvailability()

        Task { [weak self] in
            guard let self else { return }
            defer { self.isSending = false }
            do {
                let result = try await useCase.execute(
                    sessionID: self.session.id,
                    branchID: self.session.activeBranchID,
                    intervalSeconds: intervalSeconds
                )
                self.applyCounterTaskAgentResult(result)
            } catch {
                self.appendSystemMessage("Не удалось запустить Counter Task Agent: \(error.localizedDescription)")
            }
        }
    }

    private func stopCounterTaskAgent() {
        stopCounterTimer()
        guard let useCase = stopCounterTaskAgentUseCase else {
            appendSystemMessage("Counter Task Agent недоступен в этой сборке.")
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await useCase.execute(
                    sessionID: self.session.id,
                    branchID: self.session.activeBranchID
                )
                self.applyCounterTaskAgentResult(result)
                self.chatMode = .default
                self.plannerStepTitle = nil
                self.questionnaireProgressText = nil
            } catch {
                self.appendSystemMessage("Не удалось остановить Counter Task Agent: \(error.localizedDescription)")
            }
        }
    }

    private func configureCounterTaskAgentInterval(_ intervalSeconds: TimeInterval) {
        guard let useCase = configureCounterTaskAgentIntervalUseCase else {
            appendSystemMessage("Counter Task Agent недоступен в этой сборке.")
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await useCase.execute(
                    sessionID: self.session.id,
                    branchID: self.session.activeBranchID,
                    intervalSeconds: intervalSeconds
                )
                self.applyCounterTaskAgentResult(result)
            } catch {
                self.appendSystemMessage("Не удалось обновить интервал Counter Task Agent: \(error.localizedDescription)")
            }
        }
    }

    private func applyCounterTaskAgentResult(_ result: CounterTaskAgentTurnResult) {
        plannerStepTitle = result.snapshot.state.title
        questionnaireState = .empty
        questionnaireProgressText = counterTaskAgentProgressText(for: result.snapshot)
        if lastCounterTaskAgentState != result.snapshot.state {
            appendSystemMessage(
                counterTaskAgentStateListMessage(current: result.snapshot.state),
                tone: .stateTransition
            )
        }
        lastCounterTaskAgentState = result.snapshot.state
        updateApproveAvailability()
        if case let .failed(reason) = result.snapshot.state {
            appendSystemMessage("Ошибка counter task-агента: \(reason)")
        }
        for message in result.systemMessages {
            appendSystemMessage(message)
        }
        syncCounterTimer(with: result.snapshot)
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
            updateApproveAvailability()
        } catch {
            appendSystemMessage("Не удалось загрузить состояние планировщика: \(error.localizedDescription)")
        }

        if let mockUseCase = getMockTaskAgentStatusUseCase {
            do {
                let snapshot = try await mockUseCase.execute(
                    sessionID: session.id,
                    branchID: session.activeBranchID
                )
                lastMockTaskAgentState = snapshot.state
                if chatMode == .default, snapshot.state != .idle {
                    chatMode = .mockTaskAgent
                    plannerStepTitle = snapshot.state.title
                    questionnaireState = .empty
                    questionnaireProgressText = mockTaskAgentProgressText(for: snapshot)
                    appendSystemMessage(mockTaskAgentResumeHint(for: snapshot))
                }
            } catch {
                appendSystemMessage("Не удалось загрузить состояние Mock Task Agent: \(error.localizedDescription)")
            }
        }

        if let counterUseCase = getCounterTaskAgentStatusUseCase {
            do {
                let snapshot = try await counterUseCase.execute(
                    sessionID: session.id,
                    branchID: session.activeBranchID
                )
                lastCounterTaskAgentState = snapshot.state
                if chatMode == .default, snapshot.state == .running {
                    chatMode = .counterTaskAgent
                    plannerStepTitle = snapshot.state.title
                    questionnaireState = .empty
                    questionnaireProgressText = counterTaskAgentProgressText(for: snapshot)
                    appendSystemMessage(counterTaskAgentResumeHint(for: snapshot))
                }
                syncCounterTimer(with: snapshot)
            } catch {
                appendSystemMessage("Не удалось загрузить состояние Counter Task Agent: \(error.localizedDescription)")
            }
        }
    }

    private func updateApproveAvailability() {
        canApprovePlan = chatMode == .vacationPlanner && lastPlannerState == .awaitingPlanApproval
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

    private func mockTaskAgentProgressText(for snapshot: MockTaskAgentSnapshot) -> String {
        let checklistCount = snapshot.context.checklist.count
        return "Mock task: пунктов в чек-листе \(checklistCount)."
    }

    private func mockTaskAgentStateListMessage(current: MockTaskAgentState) -> String {
        let ordered: [MockTaskAgentState] = [
            .idle,
            .awaitingTask,
            .taskPrepared
        ]
        var lines: [String] = ["Состояния mock task-агента (текущее отмечено [x]):"]
        for state in ordered {
            let marker = (state == current) ? "[x]" : "[ ]"
            lines.append("\(marker) \(state.title)")
        }
        if case let .failed(reason) = current {
            lines.append("[x] Ошибка: \(reason)")
        }
        return lines.joined(separator: "\n")
    }

    private func mockTaskAgentResumeHint(for snapshot: MockTaskAgentSnapshot) -> String {
        let action: String
        switch snapshot.state {
        case .awaitingTask:
            action = "Опишите задачу в свободной форме."
        case .taskPrepared:
            action = "Отправьте новый текст, чтобы обновить чек-лист, или `reset`."
        case .failed:
            action = "Отправьте `reset` для перезапуска."
        case .idle:
            action = "Агент не активен."
        }
        return "Возобновлен Mock Task Agent: \(snapshot.state.title). \(action)"
    }

    private func counterTaskAgentProgressText(for snapshot: CounterTaskAgentSnapshot) -> String {
        let interval = formatInterval(snapshot.context.intervalSeconds)
        return "Counter task: next #\(snapshot.context.nextNumber), interval \(interval) сек."
    }

    private func counterTaskAgentStateListMessage(current: CounterTaskAgentState) -> String {
        let ordered: [CounterTaskAgentState] = [
            .idle,
            .running
        ]
        var lines: [String] = ["Состояния counter task-агента (текущее отмечено [x]):"]
        for state in ordered {
            let marker = (state == current) ? "[x]" : "[ ]"
            lines.append("\(marker) \(state.title)")
        }
        if case let .failed(reason) = current {
            lines.append("[x] Ошибка: \(reason)")
        }
        return lines.joined(separator: "\n")
    }

    private func counterTaskAgentResumeHint(for snapshot: CounterTaskAgentSnapshot) -> String {
        let interval = formatInterval(snapshot.context.intervalSeconds)
        let action: String
        switch snapshot.state {
        case .running:
            action = "Счетчик активен, интервал \(interval) сек."
        case .failed:
            action = "Отправьте `/counter start` для перезапуска."
        case .idle:
            action = "Агент не активен."
        }
        return "Возобновлен Counter Task Agent: \(snapshot.state.title). \(action)"
    }

    private func syncCounterTimer(with snapshot: CounterTaskAgentSnapshot) {
        guard snapshot.state == .running else {
            stopCounterTimer()
            return
        }
        startCounterTimer(intervalSeconds: snapshot.context.intervalSeconds)
    }

    private func startCounterTimer(intervalSeconds: TimeInterval) {
        stopCounterTimer()
        guard intervalSeconds > 0 else { return }
        let nanoseconds = UInt64(intervalSeconds * 1_000_000_000)
        counterTimerTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                await self.performCounterTickIfNeeded()
            }
        }
    }

    private func stopCounterTimer() {
        counterTimerTask?.cancel()
        counterTimerTask = nil
    }

    private func performCounterTickIfNeeded() async {
        guard chatMode == .counterTaskAgent else { return }
        guard !isCounterTickInFlight else { return }
        guard let useCase = tickCounterTaskAgentUseCase else { return }
        isCounterTickInFlight = true
        defer { isCounterTickInFlight = false }
        do {
            let result = try await useCase.execute(
                sessionID: session.id,
                branchID: session.activeBranchID
            )
            applyCounterTaskAgentResult(result)
        } catch {
            appendSystemMessage("Ошибка тика Counter Task Agent: \(error.localizedDescription)")
        }
    }

    private func parseIntervalSeconds(from value: String) -> TimeInterval? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let interval = TimeInterval(normalized), interval > 0 else {
            return nil
        }
        return interval
    }

    private func formatInterval(_ interval: TimeInterval) -> String {
        if interval.rounded(.towardZero) == interval {
            return String(format: "%.0f", interval)
        }
        return String(format: "%.2f", interval)
    }

    private var activeTaskAgentID: TaskAgentID? {
        switch chatMode {
        case .mockTaskAgent:
            return .mock
        case .counterTaskAgent:
            return .counter
        case .default, .vacationPlanner:
            return nil
        }
    }
}

private struct FormSubmissionPayload: Encodable {
    let fields: [FormSubmissionField]
}

private struct FormSubmissionField: Encodable {
    let fieldID: String
    let value: QuestionnaireValue
}

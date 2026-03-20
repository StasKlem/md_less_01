import Foundation

final class FetchVacationPlannerMCPToolsUseCase: FetchVacationPlannerMCPToolsUseCaseProtocol {
    private let toolDiscoveryService: MCPToolDiscoveryServiceProtocol
    private let endpointURL: URL

    init(
        toolDiscoveryService: MCPToolDiscoveryServiceProtocol,
        endpointURL: URL = URL(string: "stdio://open-weather")!
    ) {
        self.toolDiscoveryService = toolDiscoveryService
        self.endpointURL = endpointURL
    }

    func execute() async -> String {
        do {
            let tools = try await toolDiscoveryService.fetchTools(serverURL: endpointURL)
            return formatToolsMessage(tools)
        } catch {
            return "MCP open-weather: не удалось получить tools (\(error.localizedDescription))."
        }
    }

    private func formatToolsMessage(_ tools: [MCPToolSummary]) -> String {
        var lines: [String] = [
            "MCP open-weather подключен.",
            "Доступные tools:"
        ]

        if tools.isEmpty {
            lines.append("- список пуст")
            return lines.joined(separator: "\n")
        }

        for tool in tools {
            let description = tool.description?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if description.isEmpty {
                lines.append("- \(tool.name)")
            } else {
                lines.append("- \(tool.name): \(description)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

final class ProcessUserAnswerUseCase: ProcessUserAnswerUseCaseProtocol {
    private let answerExtractionService: AnswerExtractionServiceProtocol
    private let confidenceThreshold: Double

    init(
        answerExtractionService: AnswerExtractionServiceProtocol,
        confidenceThreshold: Double = 0.7
    ) {
        self.answerExtractionService = answerExtractionService
        self.confidenceThreshold = confidenceThreshold
    }

    func execute(
        schema: QuestionnaireSchema,
        currentState: QuestionnaireState,
        currentSlots: VacationSlots,
        userText: String,
        settings: LLMSettings,
        source: QuestionnaireAnswerSource
    ) async -> QuestionnaireProcessingResult {
        if source == .form {
            return processFormInput(
                schema: schema,
                currentState: currentState,
                currentSlots: currentSlots,
                userText: userText
            )
        }

        let extractionResult: QuestionnaireExtractionResult
        do {
            extractionResult = try await answerExtractionService.extractFields(
                userText: userText,
                schema: schema,
                currentState: currentState,
                settings: settings
            )
        } catch {
            return fallbackResult(
                schema: schema,
                state: refreshMissing(schema: schema, state: currentState),
                slots: currentSlots,
                warning: "Не удалось разобрать ответ автоматически. Уточним данные вручную.",
                fieldID: nil
            )
        }

        var nextState = currentState
        var answerUpdates: [String: QuestionnaireFieldAnswer] = [:]
        var validationErrors = extractionResult.warnings.map(\.message)
        let now = Date()
        var prioritizedFieldForClarification: String?

        for field in extractionResult.fields {
            guard let definition = schema.field(id: field.fieldID) else { continue }
            let isAmbiguous = extractionResult.warnings.contains {
                $0.fieldID == field.fieldID && $0.code == .ambiguous
            }
            if field.confidence < confidenceThreshold || isAmbiguous {
                if prioritizedFieldForClarification == nil {
                    prioritizedFieldForClarification = field.fieldID
                }
                validationErrors.append("Нужно уточнить поле \(field.fieldID): низкая уверенность.")
                continue
            }
            if validate(value: field.value, for: definition).isEmpty {
                answerUpdates[field.fieldID] = QuestionnaireFieldAnswer(
                    value: field.value,
                    confidence: field.confidence,
                    source: .llmExtraction,
                    updatedAt: now
                )
            } else {
                validationErrors.append("Поле \(field.fieldID) не прошло валидацию.")
                if prioritizedFieldForClarification == nil {
                    prioritizedFieldForClarification = field.fieldID
                }
            }
        }

        for (fieldID, answer) in answerUpdates {
            nextState.answers[fieldID] = answer
        }

        nextState = refreshMissing(schema: schema, state: nextState)
        let mergedSlots = VacationQuestionnaireSchemaAdapter.mergeSlots(current: currentSlots, updates: answerUpdates)

        if !nextState.missingHard.isEmpty {
            let nextField = prioritizedFieldForClarification ?? nextState.missingHard[0]
            return QuestionnaireProcessingResult(
                state: nextState,
                updatedSlots: mergedSlots,
                validationErrors: validationErrors,
                action: .askNextQuestion(
                    fieldID: nextField,
                    warning: validationErrors.isEmpty ? nil : validationErrors.joined(separator: " ")
                )
            )
        }
        if !nextState.missingSoft.isEmpty {
            return QuestionnaireProcessingResult(
                state: nextState,
                updatedSlots: mergedSlots,
                validationErrors: validationErrors,
                action: .warnSoftMissing(
                    message: "Критичные данные собраны. Можно продолжать, но полезно уточнить: \(nextState.missingSoft.joined(separator: ", ")).",
                    suggestedFieldID: nextState.missingSoft[0]
                )
            )
        }
        return QuestionnaireProcessingResult(
            state: nextState,
            updatedSlots: mergedSlots,
            validationErrors: validationErrors,
            action: .proceed
        )
    }

    private func fallbackResult(
        schema: QuestionnaireSchema,
        state: QuestionnaireState,
        slots: VacationSlots,
        warning: String,
        fieldID: String?
    ) -> QuestionnaireProcessingResult {
        let action: QuestionnaireNextAction
        if let fieldID = fieldID ?? state.missingHard.first ?? state.missingSoft.first {
            action = .askNextQuestion(fieldID: fieldID, warning: warning)
        } else {
            action = .warnSoftMissing(message: warning, suggestedFieldID: nil)
        }
        return QuestionnaireProcessingResult(
            state: state,
            updatedSlots: slots,
            validationErrors: [warning],
            action: action
        )
    }

    private func processFormInput(
        schema: QuestionnaireSchema,
        currentState: QuestionnaireState,
        currentSlots: VacationSlots,
        userText: String
    ) -> QuestionnaireProcessingResult {
        do {
            let data = Data(userText.utf8)
            let payload = try JSONDecoder().decode(FormInputPayload.self, from: data)
            let now = Date()
            var updates: [String: QuestionnaireFieldAnswer] = [:]
            for field in payload.fields {
                guard let definition = schema.field(id: field.fieldID) else { continue }
                guard validate(value: field.value, for: definition).isEmpty else { continue }
                updates[field.fieldID] = QuestionnaireFieldAnswer(
                    value: field.value,
                    confidence: 1.0,
                    source: .form,
                    updatedAt: now
                )
            }
            var next = currentState
            for (key, value) in updates {
                next.answers[key] = value
            }
            next = refreshMissing(schema: schema, state: next)
            let merged = VacationQuestionnaireSchemaAdapter.mergeSlots(current: currentSlots, updates: updates)
            if !next.missingHard.isEmpty {
                return QuestionnaireProcessingResult(
                    state: next,
                    updatedSlots: merged,
                    validationErrors: [],
                    action: .askNextQuestion(fieldID: next.missingHard[0], warning: nil)
                )
            }
            if !next.missingSoft.isEmpty {
                return QuestionnaireProcessingResult(
                    state: next,
                    updatedSlots: merged,
                    validationErrors: [],
                    action: .warnSoftMissing(
                        message: "Критичные данные собраны. Можно продолжать, но полезно уточнить: \(next.missingSoft.joined(separator: ", ")).",
                        suggestedFieldID: next.missingSoft[0]
                    )
                )
            }
            return QuestionnaireProcessingResult(
                state: next,
                updatedSlots: merged,
                validationErrors: [],
                action: .proceed
            )
        } catch {
            return fallbackResult(
                schema: schema,
                state: refreshMissing(schema: schema, state: currentState),
                slots: currentSlots,
                warning: "Не удалось применить данные формы. Проверьте заполнение полей.",
                fieldID: nil
            )
        }
    }

    private func refreshMissing(schema: QuestionnaireSchema, state: QuestionnaireState) -> QuestionnaireState {
        var next = state
        next.missingHard = schema.fields
            .filter { $0.requiredLevel == .hard && next.answers[$0.id] == nil }
            .map(\.id)
        next.missingSoft = schema.fields
            .filter { $0.requiredLevel == .soft && next.answers[$0.id] == nil }
            .map(\.id)
        return next
    }

    private func validate(value: QuestionnaireValue, for field: QuestionnaireFieldDefinition) -> [String] {
        var errors: [String] = []
        for rule in field.validators {
            switch rule {
            case .nonEmptyText:
                if case let .text(text) = value {
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        errors.append(field.id)
                    }
                } else {
                    errors.append(field.id)
                }
            case .validDateRange:
                if case let .dateRange(range) = value {
                    if range.start > range.end {
                        errors.append(field.id)
                    }
                } else {
                    errors.append(field.id)
                }
            case .positiveMoneyAmount:
                if case let .money(money) = value {
                    if money.total <= 0 {
                        errors.append(field.id)
                    }
                } else {
                    errors.append(field.id)
                }
            case .positiveInteger:
                if case let .integer(number) = value {
                    if number < 1 {
                        errors.append(field.id)
                    }
                } else {
                    errors.append(field.id)
                }
            case .nonEmptyList:
                if case let .stringList(values) = value {
                    if values.isEmpty {
                        errors.append(field.id)
                    }
                } else {
                    errors.append(field.id)
                }
            }
        }
        return errors
    }
}

private struct FormInputPayload: Decodable {
    let fields: [FormInputField]
}

private struct FormInputField: Decodable {
    let fieldID: String
    let value: QuestionnaireValue
}

final class VacationPlannerReducer: VacationPlannerReducerProtocol {
    func reduce(
        snapshot: VacationPlanningSnapshot,
        event: VacationPlanningEvent
    ) -> VacationPlanningTransitionResult {
        let shouldValidateInvariants = snapshot.state == .validatingDestination
        if shouldValidateInvariants {
            let preViolations = VacationPlanningInvariantValidator.validate(
                state: snapshot.state,
                context: snapshot.context,
                snapshotUpdatedAt: snapshot.updatedAt
            )
            if !preViolations.isEmpty {
                return failedTransition(
                    context: snapshot.context,
                    reason: "Нарушение инварианта: \(preViolations.map(\.message).joined(separator: ", "))"
                )
            }
        }

        let transition: VacationPlanningTransitionResult
        switch (snapshot.state, event) {
        case (.idle, .started), (.failed, .started):
            transition = startTransition(snapshot: snapshot)
        case (.idle, .userMessage):
            transition = startTransition(snapshot: snapshot)
        case (_, let .errorOccurred(error)):
            transition = failedTransition(context: snapshot.context, reason: error.failureReason)
        case (.destinationRequest, let .userMessage(text, source)),
             (.failed, let .userMessage(text, source)):
            transition = userMessageTransition(snapshot: snapshot, text: text, source: source)
        case (.validatingDestination, .questionnaireProcessed(let result)):
            transition = questionnaireProcessedTransition(snapshot: snapshot, result: result)
        case (.awaitingPlanApproval, .planApproved):
            transition = planApprovalTransition(snapshot: snapshot)
        case (.awaitingPlanApproval, .revisionRequested(let comment)):
            transition = revisionTransition(context: snapshot.context, comment: comment)
        case (.generateResult, .optionsGenerated(let options)):
            transition = optionsGeneratedTransition(snapshot: snapshot, options: options)
        case (.generateResult, .itineraryGenerated(let itinerary)):
            var context = snapshot.context
            context.itinerary = itinerary
            context.itineraryBuiltAt = Date()
            transition = VacationPlanningTransitionResult(
                nextState: .generateResult,
                nextContext: context,
                effects: [.calculateBudget, .persistSnapshot]
            )
        case (.generateResult, .budgetCalculated(let budget)):
            transition = finalizeGeneratedPlanTransition(snapshot: snapshot, budget: budget)
        default:
            transition = blockedTransition(
                snapshot: snapshot,
                reason: "Переход запрещен: из состояния «\(snapshot.state.title)» нельзя выполнить «\(event.debugName)»."
            )
        }

        let now = Date()
        var validatedContext = transition.nextContext
        validatedContext.updatedAt = now
        if shouldValidateInvariants {
            let postViolations = VacationPlanningInvariantValidator.validate(
                state: transition.nextState,
                context: validatedContext,
                snapshotUpdatedAt: now
            )
            if !postViolations.isEmpty {
                return failedTransition(
                    context: validatedContext,
                    reason: "Нарушение инварианта: \(postViolations.map(\.message).joined(separator: ", "))"
                )
            }
        }

        return VacationPlanningTransitionResult(
            nextState: transition.nextState,
            nextContext: validatedContext,
            effects: transition.effects
        )
    }

    private func userMessageTransition(
        snapshot: VacationPlanningSnapshot,
        text: String,
        source: QuestionnaireAnswerSource
    ) -> VacationPlanningTransitionResult {
        var context = snapshot.context
        context.lastUserMessage = text
        return VacationPlanningTransitionResult(
            nextState: .validatingDestination,
            nextContext: context,
            effects: [.processUserAnswer(text, source), .persistSnapshot]
        )
    }

    private func questionnaireProcessedTransition(
        snapshot: VacationPlanningSnapshot,
        result: QuestionnaireProcessingResult
    ) -> VacationPlanningTransitionResult {
        var context = snapshot.context
        context.questionnaireState = result.state
        context.slots = result.updatedSlots
        context.lastValidationErrors = result.validationErrors

        guard isDestinationValid(in: context) else {
            let warning: String?
            switch result.action {
            case let .askNextQuestion(fieldID, message):
                warning = fieldID == VacationQuestionnaireSchemaAdapter.destinationFieldID
                    ? message
                    : "Не удалось подтвердить место назначения. Уточните направление."
            case let .warnSoftMissing(message, _):
                warning = message
            case .proceed:
                warning = "Не удалось подтвердить место назначения. Уточните направление."
            }
            return VacationPlanningTransitionResult(
                nextState: .destinationRequest,
                nextContext: context,
                effects: [.askQuestion(fieldID: VacationQuestionnaireSchemaAdapter.destinationFieldID, warning: warning), .persistSnapshot]
            )
        }

        context.lastValidationErrors = []
        return VacationPlanningTransitionResult(
            nextState: .awaitingPlanApproval,
            nextContext: context,
            effects: [.askUser(questionKey: .approval), .persistSnapshot]
        )
    }

    private func optionsGeneratedTransition(
        snapshot: VacationPlanningSnapshot,
        options: [VacationOption]
    ) -> VacationPlanningTransitionResult {
        var context = snapshot.context
        context.options = options
        context.selectedOption = options.first
        if options.isEmpty {
            return VacationPlanningTransitionResult(
                nextState: .destinationRequest,
                nextContext: context,
                effects: [
                    .askQuestion(
                        fieldID: VacationQuestionnaireSchemaAdapter.destinationFieldID,
                        warning: "Не удалось подобрать варианты по текущему направлению. Уточните destination."
                    ),
                    .persistSnapshot,
                ]
            )
        }
        return VacationPlanningTransitionResult(
            nextState: .generateResult,
            nextContext: context,
            effects: [.generateItinerary, .persistSnapshot]
        )
    }

    private func planApprovalTransition(snapshot: VacationPlanningSnapshot) -> VacationPlanningTransitionResult {
        var context = snapshot.context
        guard isDestinationValid(in: context) else {
            return blockedTransition(
                snapshot: snapshot,
                reason: "Нельзя утвердить план без валидного destination."
            )
        }
        context.planApprovedAt = Date()
        context.finalPlan = nil
        context.isFinalPlanLocked = false
        return VacationPlanningTransitionResult(
            nextState: .generateResult,
            nextContext: context,
            effects: [.generateDestinationOptions, .persistSnapshot]
        )
    }

    private func finalizeGeneratedPlanTransition(
        snapshot: VacationPlanningSnapshot,
        budget: VacationBudgetBreakdown
    ) -> VacationPlanningTransitionResult {
        var context = snapshot.context
        guard let itinerary = context.itinerary else {
            return failedTransition(
                context: context,
                reason: "Нельзя собрать финальный план без маршрута."
            )
        }

        context.budgetBreakdown = budget
        context.budgetReviewedAt = Date()
        context.validationPassedAt = Date()
        context.finalPlan = VacationPlan(
            sessionID: snapshot.sessionID,
            branchID: snapshot.branchID,
            slots: context.slots,
            selectedOption: context.selectedOption,
            itinerary: itinerary,
            budget: budget,
            weatherSummary: nil,
            createdAt: Date()
        )
        context.isFinalPlanLocked = true
        return VacationPlanningTransitionResult(
            nextState: .idle,
            nextContext: context,
            effects: [.emitFinalPlan, .persistSnapshot]
        )
    }

    private func revisionTransition(
        context: VacationPlanningContext,
        comment: String
    ) -> VacationPlanningTransitionResult {
        var next = context
        next.revisionCount += 1
        next.isFinalPlanLocked = false
        next.finalPlan = nil
        next.planApprovedAt = nil
        next.executionCompletedAt = nil
        next.validationPassedAt = nil
        next.itinerary = nil
        next.itineraryBuiltAt = nil
        next.budgetBreakdown = nil
        next.budgetReviewedAt = nil
        next.options = []
        next.selectedOption = nil
        next.slots.destination = nil
        next.questionnaireState.answers.removeValue(forKey: VacationQuestionnaireSchemaAdapter.destinationFieldID)
        next.questionnaireState = refreshQuestionnaireState(next.questionnaireState, slots: next.slots)
        if !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            next.constraintsAppend(comment)
        }
        return VacationPlanningTransitionResult(
            nextState: .destinationRequest,
            nextContext: next,
            effects: [.askQuestion(fieldID: VacationQuestionnaireSchemaAdapter.destinationFieldID, warning: nil), .persistSnapshot]
        )
    }

    private func failedTransition(
        context: VacationPlanningContext,
        reason: String
    ) -> VacationPlanningTransitionResult {
        VacationPlanningTransitionResult(
            nextState: .failed(reason: reason),
            nextContext: context,
            effects: [.askUser(questionKey: .retryAfterError), .persistSnapshot]
        )
    }

    private func blockedTransition(
        snapshot: VacationPlanningSnapshot,
        reason: String
    ) -> VacationPlanningTransitionResult {
        let guidance: VacationQuestionKey
        switch snapshot.state {
        case .destinationRequest, .validatingDestination:
            guidance = .missingDestination
        case .awaitingPlanApproval:
            guidance = .approval
        case .generateResult:
            guidance = .retryAfterError
        default:
            guidance = .retryAfterError
        }
        return VacationPlanningTransitionResult(
            nextState: snapshot.state,
            nextContext: snapshot.context,
            effects: [.notifyUser(reason), .askUser(questionKey: guidance), .persistSnapshot]
        )
    }

    private func refreshQuestionnaireState(
        _ current: QuestionnaireState,
        slots: VacationSlots
    ) -> QuestionnaireState {
        var next = current
        if next.answers.isEmpty {
            next = VacationQuestionnaireSchemaAdapter.makeInitialState(from: slots)
        }
        next.missingHard = VacationQuestionnaireSchemaAdapter.schema.fields
            .filter { $0.requiredLevel == .hard && next.answers[$0.id] == nil }
            .map(\.id)
        next.missingSoft = VacationQuestionnaireSchemaAdapter.schema.fields
            .filter { $0.requiredLevel == .soft && next.answers[$0.id] == nil }
            .map(\.id)
        return next
    }

    private func startTransition(snapshot: VacationPlanningSnapshot) -> VacationPlanningTransitionResult {
        var context = snapshot.context
        context.lastValidationErrors = []
        context.planApprovedAt = nil
        context.executionCompletedAt = nil
        context.validationPassedAt = nil
        context.finalPlan = nil
        context.isFinalPlanLocked = false
        context.itinerary = nil
        context.itineraryBuiltAt = nil
        context.budgetBreakdown = nil
        context.budgetReviewedAt = nil
        context.options = []
        context.selectedOption = nil
        context.questionnaireState = refreshQuestionnaireState(context.questionnaireState, slots: context.slots)
        return VacationPlanningTransitionResult(
            nextState: .destinationRequest,
            nextContext: context,
            effects: [.askQuestion(fieldID: VacationQuestionnaireSchemaAdapter.destinationFieldID, warning: nil), .persistSnapshot]
        )
    }

    private func isDestinationValid(in context: VacationPlanningContext) -> Bool {
        guard let destination = context.slots.destination?.trimmingCharacters(in: .whitespacesAndNewlines),
              !destination.isEmpty else {
            return false
        }
        return true
    }

    private func userInputInvariantViolations(for slots: VacationSlots) -> [(fieldID: String, message: String)] {
        var violations: [(fieldID: String, message: String)] = []
        if let range = slots.dateRange, range.start > range.end {
            violations.append((
                fieldID: VacationQuestionnaireSchemaAdapter.datesFieldID,
                message: "Дата начала поездки должна быть не позже даты окончания."
            ))
        }
        if let budget = slots.budget, budget.total <= 0 {
            violations.append((
                fieldID: VacationQuestionnaireSchemaAdapter.budgetFieldID,
                message: "Бюджет должен быть больше 0."
            ))
        }
        return violations
    }
}

final class StartVacationPlanningUseCase: StartVacationPlanningUseCaseProtocol {
    private let orchestrator: VacationPlanningOrchestrator

    init(orchestrator: VacationPlanningOrchestrator) {
        self.orchestrator = orchestrator
    }

    func execute(sessionID: UUID, branchID: UUID) async throws -> VacationPlanningTurnResult {
        try await orchestrator.process(
            sessionID: sessionID,
            branchID: branchID,
            initialEvent: .started
        )
    }
}

final class HandleVacationPlanningEventUseCase: HandleVacationPlanningEventUseCaseProtocol {
    private let orchestrator: VacationPlanningOrchestrator

    init(orchestrator: VacationPlanningOrchestrator) {
        self.orchestrator = orchestrator
    }

    func execute(
        sessionID: UUID,
        branchID: UUID,
        userText: String,
        source: QuestionnaireAnswerSource
    ) async throws -> VacationPlanningTurnResult {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased() == "approve" {
            return try await orchestrator.process(sessionID: sessionID, branchID: branchID, initialEvent: .planApproved)
        }
        if trimmed.lowercased().hasPrefix("revise:") {
            let comment = String(trimmed.dropFirst("revise:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return try await orchestrator.process(
                sessionID: sessionID,
                branchID: branchID,
                initialEvent: .revisionRequested(comment: comment)
            )
        }
        return try await orchestrator.process(
            sessionID: sessionID,
            branchID: branchID,
            initialEvent: .userMessage(text: userText, source: source)
        )
    }
}

final class GetVacationPlanningStatusUseCase: GetVacationPlanningStatusUseCaseProtocol {
    private let stateRepository: VacationPlanningStateRepositoryProtocol

    init(stateRepository: VacationPlanningStateRepositoryProtocol) {
        self.stateRepository = stateRepository
    }

    func execute(sessionID: UUID, branchID: UUID) async throws -> VacationPlanningSnapshot {
        if let snapshot = try await stateRepository.fetchSnapshot(sessionID: sessionID, branchID: branchID) {
            return snapshot
        }
        return VacationPlanningSnapshot(
            schemaVersion: VacationPlanningSnapshot.schemaVersionCurrent,
            sessionID: sessionID,
            branchID: branchID,
            state: .idle,
            context: .initial,
            updatedAt: Date()
        )
    }
}

final class FinalizeVacationPlanUseCase: FinalizeVacationPlanUseCaseProtocol {
    private let stateRepository: VacationPlanningStateRepositoryProtocol
    private let planRepository: VacationPlanRepositoryProtocol

    init(
        stateRepository: VacationPlanningStateRepositoryProtocol,
        planRepository: VacationPlanRepositoryProtocol
    ) {
        self.stateRepository = stateRepository
        self.planRepository = planRepository
    }

    func execute(sessionID: UUID, branchID: UUID) async throws -> VacationPlan {
        if let persisted = try await planRepository.fetchFinalPlan(sessionID: sessionID, branchID: branchID) {
            return persisted
        }
        guard let snapshot = try await stateRepository.fetchSnapshot(sessionID: sessionID, branchID: branchID) else {
            throw VacationPlanningError.serviceFailure("Снимок планирования отсутствует.")
        }
        guard case .idle = snapshot.state,
              snapshot.context.isFinalPlanLocked,
              let plan = snapshot.context.finalPlan else {
            throw VacationPlanningError.invalidTransition("Финальный план недоступен: дождитесь завершения состояния generateResult.")
        }
        try await planRepository.saveFinalPlan(plan)
        return plan
    }
}

final class VacationPlanningOrchestrator {
    private let stateRepository: VacationPlanningStateRepositoryProtocol
    private let planRepository: VacationPlanRepositoryProtocol
    private let settingsRepository: SettingsRepositoryProtocol
    private let reducer: VacationPlannerReducerProtocol
    private let processUserAnswerUseCase: ProcessUserAnswerUseCaseProtocol
    private let questionGenerationService: QuestionGenerationServiceProtocol
    private let questionnaireSchema: QuestionnaireSchema
    private let optionGenerationService: VacationOptionGenerationServiceProtocol
    private let itineraryService: VacationItineraryServiceProtocol
    private let budgetEstimator: VacationBudgetEstimatorProtocol
    private let mcpWeatherService: MCPWeatherServiceProtocol?
    private let mcpWeatherEndpointURL: URL

    init(
        stateRepository: VacationPlanningStateRepositoryProtocol,
        planRepository: VacationPlanRepositoryProtocol,
        settingsRepository: SettingsRepositoryProtocol,
        reducer: VacationPlannerReducerProtocol,
        processUserAnswerUseCase: ProcessUserAnswerUseCaseProtocol,
        questionGenerationService: QuestionGenerationServiceProtocol,
        questionnaireSchema: QuestionnaireSchema,
        optionGenerationService: VacationOptionGenerationServiceProtocol,
        itineraryService: VacationItineraryServiceProtocol,
        budgetEstimator: VacationBudgetEstimatorProtocol,
        mcpWeatherService: MCPWeatherServiceProtocol? = nil,
        mcpWeatherEndpointURL: URL = URL(string: "stdio://open-weather")!
    ) {
        self.stateRepository = stateRepository
        self.planRepository = planRepository
        self.settingsRepository = settingsRepository
        self.reducer = reducer
        self.processUserAnswerUseCase = processUserAnswerUseCase
        self.questionGenerationService = questionGenerationService
        self.questionnaireSchema = questionnaireSchema
        self.optionGenerationService = optionGenerationService
        self.itineraryService = itineraryService
        self.budgetEstimator = budgetEstimator
        self.mcpWeatherService = mcpWeatherService
        self.mcpWeatherEndpointURL = mcpWeatherEndpointURL
    }

    func process(
        sessionID: UUID,
        branchID: UUID,
        initialEvent: VacationPlanningEvent
    ) async throws -> VacationPlanningTurnResult {
        var snapshot = try await loadSnapshot(sessionID: sessionID, branchID: branchID)
        let settings = (try? await settingsRepository.fetchSettings(sessionID: sessionID)) ?? .default
        var queue: [VacationPlanningEvent] = [initialEvent]
        var messages: [String] = []

        while !queue.isEmpty {
            let event = queue.removeFirst()
            let transition = reducer.reduce(snapshot: snapshot, event: event)
            snapshot = rebuildSnapshot(from: transition, previous: snapshot)

            let execution = try await executeEffects(transition.effects, snapshot: snapshot, settings: settings)
            messages.append(contentsOf: execution.messages)
            queue.append(contentsOf: execution.events)

        }

        try await stateRepository.saveSnapshot(snapshot)
        return VacationPlanningTurnResult(snapshot: snapshot, agentMessages: messages)
    }

    private func loadSnapshot(sessionID: UUID, branchID: UUID) async throws -> VacationPlanningSnapshot {
        if let existing = try await stateRepository.fetchSnapshot(sessionID: sessionID, branchID: branchID) {
            return existing
        }
        return VacationPlanningSnapshot(
            schemaVersion: VacationPlanningSnapshot.schemaVersionCurrent,
            sessionID: sessionID,
            branchID: branchID,
            state: .idle,
            context: .initial,
            updatedAt: Date()
        )
    }

    private func rebuildSnapshot(
        from transition: VacationPlanningTransitionResult,
        previous: VacationPlanningSnapshot
    ) -> VacationPlanningSnapshot {
        let now = Date()
        var context = transition.nextContext
        context.updatedAt = now
        if context.createdAt > now {
            context.createdAt = now
        }
        return VacationPlanningSnapshot(
            schemaVersion: VacationPlanningSnapshot.schemaVersionCurrent,
            sessionID: previous.sessionID,
            branchID: previous.branchID,
            state: transition.nextState,
            context: context,
            updatedAt: now
        )
    }

    private func executeEffects(
        _ effects: [VacationEffect],
        snapshot: VacationPlanningSnapshot,
        settings: LLMSettings
    ) async throws -> (events: [VacationPlanningEvent], messages: [String]) {
        var resultingEvents: [VacationPlanningEvent] = []
        var messages: [String] = []

        for effect in effects {
            switch effect {
            case let .notifyUser(message):
                messages.append(message)
            case let .askUser(questionKey):
                if questionKey == .approval {
                    messages.append(approvalQuestionText(context: snapshot.context))
                } else {
                    messages.append(questionText(for: questionKey))
                }
            case let .askQuestion(fieldID, warning):
                let prompt = await buildQuestionPrompt(fieldID: fieldID, snapshot: snapshot, settings: settings)
                if let warning, !warning.isEmpty {
                    messages.append(warning)
                }
                messages.append(prompt.text)
            case let .processUserAnswer(text, source):
                let result = await processUserAnswerUseCase.execute(
                    schema: questionnaireSchema,
                    currentState: snapshot.context.questionnaireState,
                    currentSlots: snapshot.context.slots,
                    userText: text,
                    settings: settings,
                    source: source
                )
                resultingEvents.append(.questionnaireProcessed(result))
            case .generateDestinationOptions:
                let options = try await optionGenerationService.generateOptions(context: snapshot.context)
                resultingEvents.append(.optionsGenerated(options))
            case .generateItinerary:
                let itinerary = try await itineraryService.generateItinerary(context: snapshot.context)
                resultingEvents.append(.itineraryGenerated(itinerary))
            case .calculateBudget:
                let budget = try await budgetEstimator.estimateBudget(context: snapshot.context)
                resultingEvents.append(.budgetCalculated(budget))
            case .persistSnapshot:
                try await stateRepository.saveSnapshot(snapshot)
            case .emitFinalPlan:
                if let plan = snapshot.context.finalPlan {
                    if let weatherRequestMessage = mcpWeatherRequestMessage(for: plan) {
                        messages.append(weatherRequestMessage)
                    }
                    let weatherEnrichedPlan = await enrichPlanWithWeather(plan)
                    try await planRepository.saveFinalPlan(weatherEnrichedPlan)
                    messages.append("План отпуска готов и сохранен.")
                    messages.append(finalPlanMessage(weatherEnrichedPlan))
                } else {
                    throw VacationPlanningError.serviceFailure("Невозможно опубликовать итоговый план без завершенного контекста.")
                }
            }
        }

        return (resultingEvents, messages)
    }

    private func buildQuestionPrompt(
        fieldID: String?,
        snapshot: VacationPlanningSnapshot,
        settings: LLMSettings
    ) async -> QuestionPrompt {
        let state = snapshot.context.questionnaireState
        let nextFieldID = fieldID ?? state.missingHard.first ?? state.missingSoft.first
        let target = nextFieldID.flatMap { questionnaireSchema.field(id: $0) }
        do {
            return try await questionGenerationService.generateQuestion(
                context: QuestionnaireQuestionContext(
                    schema: questionnaireSchema,
                    state: state,
                    latestUserMessage: snapshot.context.lastUserMessage,
                    settings: settings
                ),
                targetField: target,
                toneHints: ["neutral", "short"]
            )
        } catch {
            return QuestionPrompt(
                fieldID: target?.id,
                text: target?.fallbackQuestion ?? "Уточните, пожалуйста, недостающие детали поездки.",
                suggestions: [],
                isFallback: true
            )
        }
    }

    private func questionText(for key: VacationQuestionKey) -> String {
        switch key {
        case .provideBasics:
            return "Укажите место назначения для планирования отдыха."
        case .missingDestination:
            return "Уточните место назначения, чтобы продолжить."
        case .missingDates:
            return "Сейчас важно только место назначения. Укажите destination."
        case .missingBudget:
            return "Бюджет будет рассчитан после подтверждения destination."
        case .approval:
            return "Подтвердите destination: `approve` или запросите изменение `revise: ...`."
        case .executeApprovedPlan:
            return "Генерирую финальный план отдыха."
        case .validateBeforeFinal:
            return "План готовится, подождите."
        case .finalizeReady:
            return "Финальный план готов."
        case .retryAfterError:
            return "Этот шаг недоступен в текущем состоянии. Следуйте допустимым переходам FSM."
        }
    }

    private func approvalQuestionText(context: VacationPlanningContext) -> String {
        var lines: [String] = ["Проверьте собранные данные перед подтверждением плана:"]

        if let destination = context.slots.destination?.trimmingCharacters(in: .whitespacesAndNewlines), !destination.isEmpty {
            lines.append("- destination: \(destination)")
        }
        if let range = context.slots.dateRange {
            lines.append("- dates: \(format(date: range.start)) — \(format(date: range.end))")
        }
        if let budget = context.slots.budget {
            lines.append("- budget: \(budget.total) \(budget.currency)")
        }

        lines.append("- travelers: \(context.slots.travelerCount)")

        if let travelStyle = context.slots.travelStyle?.trimmingCharacters(in: .whitespacesAndNewlines), !travelStyle.isEmpty {
            lines.append("- travel_style: \(travelStyle)")
        }
        if !context.slots.interests.isEmpty {
            lines.append("- interests: \(context.slots.interests.joined(separator: ", "))")
        }
        if !context.slots.constraints.isEmpty {
            lines.append("- constraints: \(context.slots.constraints.joined(separator: ", "))")
        }

        lines.append("Подтвердите план: `approve` или запросите изменение `revise: ...`.")
        return lines.joined(separator: "\n")
    }

    private func format(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func finalPlanMessage(_ plan: VacationPlan) -> String {
        var lines: [String] = ["Финальный план отпуска:"]

        if let destination = plan.slots.destination?.trimmingCharacters(in: .whitespacesAndNewlines), !destination.isEmpty {
            lines.append("- destination: \(destination)")
        }
        if let range = plan.slots.dateRange {
            lines.append("- dates: \(format(date: range.start)) — \(format(date: range.end))")
        }
        if let selectedOption = plan.selectedOption {
            lines.append("- option: \(selectedOption.title)")
        }
        lines.append("- budget total: \(plan.budget.total) \(plan.budget.currency)")

        if let weatherSummary = plan.weatherSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !weatherSummary.isEmpty
        {
            lines.append("Погода (MCP):")
            weatherSummary
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map(String.init)
                .forEach { lines.append("  \($0)") }
        }

        if !plan.itinerary.days.isEmpty {
            lines.append("Маршрут:")
            for day in plan.itinerary.days {
                let activities = day.activities.joined(separator: ", ")
                lines.append("  День \(day.dayIndex): \(day.title) (\(activities))")
            }
        }
        if !plan.itinerary.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Заметки: \(plan.itinerary.notes)")
        }

        return lines.joined(separator: "\n")
    }

    private func enrichPlanWithWeather(_ plan: VacationPlan) async -> VacationPlan {
        guard let service = mcpWeatherService,
              let destination = plan.slots.destination?.trimmingCharacters(in: .whitespacesAndNewlines),
              !destination.isEmpty else {
            return plan
        }

        let weatherSummary: String
        do {
            weatherSummary = try await service.fetchCurrentWeather(
                serverURL: mcpWeatherEndpointURL,
                city: destination,
                units: "metric",
                language: "ru"
            )
        } catch {
            weatherSummary = "Не удалось получить погоду через MCP (\(error.localizedDescription))."
        }

        let normalizedSummary = weatherSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSummary.isEmpty else { return plan }

        return VacationPlan(
            sessionID: plan.sessionID,
            branchID: plan.branchID,
            slots: plan.slots,
            selectedOption: plan.selectedOption,
            itinerary: plan.itinerary,
            budget: plan.budget,
            weatherSummary: normalizedSummary,
            createdAt: plan.createdAt
        )
    }

    private func mcpWeatherRequestMessage(for plan: VacationPlan) -> String? {
        guard mcpWeatherService != nil,
              let destination = plan.slots.destination?.trimmingCharacters(in: .whitespacesAndNewlines),
              !destination.isEmpty else {
            return nil
        }
        return "MCP open-weather: запрашиваю актуальную погоду для \(destination)."
    }
}

private extension VacationPlanningContext {
    mutating func constraintsAppend(_ comment: String) {
        let normalized = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        let nextConstraints = slots.constraints.mergingUnique(with: [normalized])
        slots = VacationSlots(
            destination: slots.destination,
            dateRange: slots.dateRange,
            budget: slots.budget,
            travelerCount: slots.travelerCount,
            travelStyle: slots.travelStyle,
            interests: slots.interests,
            constraints: nextConstraints
        )
    }
}

private extension VacationPlanningEvent {
    var debugName: String {
        switch self {
        case .started:
            return "запуск"
        case .userMessage:
            return "сообщениеПользователя"
        case .questionnaireProcessed:
            return "анкетаОбработана"
        case .optionsGenerated:
            return "вариантыСгенерированы"
        case .itineraryGenerated:
            return "маршрутСгенерирован"
        case .budgetCalculated:
            return "бюджетРассчитан"
        case .planApproved:
            return "планУтвержден"
        case .executionCompleted:
            return "реализацияЗавершена"
        case .validationPassed:
            return "валидацияУспешна"
        case .validationFailed:
            return "валидацияПровалена"
        case .finalizeRequested:
            return "финализацияЗапрошена"
        case .revisionRequested:
            return "запрошенаПравка"
        case .errorOccurred:
            return "ошибка"
        }
    }
}

private extension VacationPlanningError {
    var failureReason: String {
        switch self {
        case let .invariantViolation(violations):
            return violations.map(\.message).joined(separator: ", ")
        case let .invalidTransition(message):
            return message
        case let .serviceFailure(message):
            return message
        }
    }
}

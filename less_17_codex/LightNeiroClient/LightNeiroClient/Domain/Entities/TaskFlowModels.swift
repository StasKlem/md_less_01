import Foundation

enum VacationPlanningState: Equatable, Codable {
    case idle
    case destinationRequest
    case validatingDestination
    case awaitingPlanApproval
    case generateResult
    case failed(reason: String)

    var title: String {
        switch self {
        case .idle:
            return "Ожидание"
        case .destinationRequest:
            return "Запрос места назначения"
        case .validatingDestination:
            return "Проверка места назначения"
        case .awaitingPlanApproval:
            return "Ожидание утверждения плана"
        case .generateResult:
            return "Генерация финального плана"
        case let .failed(reason):
            return "Ошибка: \(reason)"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case reason
    }

    private enum Kind: String, Codable {
        case idle
        case destinationRequest
        case awaitingDestination
        case validatingDestination
        case awaitingPlanApproval
        case generateResult
        // Backward compatibility for persisted snapshots.
        case collectingRequirements
        case clarifyingMissingData
        case generatingOptions
        case buildingItinerary
        case budgetReview
        case approvedForExecution
        case validatingResult
        case awaitingApproval
        case completed
        case failed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .idle:
            self = .idle
        case .destinationRequest:
            self = .destinationRequest
        case .awaitingDestination:
            self = .destinationRequest
        case .validatingDestination:
            self = .validatingDestination
        case .awaitingPlanApproval:
            self = .awaitingPlanApproval
        case .generateResult:
            self = .generateResult
        case .collectingRequirements, .clarifyingMissingData, .generatingOptions, .buildingItinerary, .budgetReview:
            self = .destinationRequest
        case .approvedForExecution, .validatingResult:
            self = .awaitingPlanApproval
        case .awaitingApproval:
            self = .awaitingPlanApproval
        case .completed:
            self = .idle
        case .failed:
            self = .failed(reason: try container.decode(String.self, forKey: .reason))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .idle:
            try container.encode(Kind.idle, forKey: .kind)
        case .destinationRequest:
            try container.encode(Kind.destinationRequest, forKey: .kind)
        case .validatingDestination:
            try container.encode(Kind.validatingDestination, forKey: .kind)
        case .awaitingPlanApproval:
            try container.encode(Kind.awaitingPlanApproval, forKey: .kind)
        case .generateResult:
            try container.encode(Kind.generateResult, forKey: .kind)
        case let .failed(reason):
            try container.encode(Kind.failed, forKey: .kind)
            try container.encode(reason, forKey: .reason)
        }
    }
}

struct VacationDateRange: Codable, Equatable {
    let start: Date
    let end: Date
}

struct VacationBudgetInput: Codable, Equatable {
    let total: Double
    let currency: String
}

struct VacationSlots: Codable, Equatable {
    var destination: String?
    var dateRange: VacationDateRange?
    var budget: VacationBudgetInput?
    var travelerCount: Int
    var travelStyle: String?
    var interests: [String]
    var constraints: [String]

    init(
        destination: String? = nil,
        dateRange: VacationDateRange? = nil,
        budget: VacationBudgetInput? = nil,
        travelerCount: Int = 1,
        travelStyle: String? = nil,
        interests: [String] = [],
        constraints: [String] = []
    ) {
        self.destination = destination
        self.dateRange = dateRange
        self.budget = budget
        self.travelerCount = travelerCount
        self.travelStyle = travelStyle
        self.interests = interests
        self.constraints = constraints
    }

    var hasMinimumInput: Bool {
        dateRange != nil && budget != nil && (destination != nil || travelStyle != nil)
    }
}

enum QuestionnaireFieldType: String, Codable, Equatable {
    case text
    case dateRange
    case money
    case integer
    case stringList
}

enum RequiredLevel: String, Codable, Equatable {
    case hard
    case soft
}

enum QuestionnaireValidationRule: String, Codable, Equatable {
    case nonEmptyText
    case validDateRange
    case positiveMoneyAmount
    case positiveInteger
    case nonEmptyList
}

struct QuestionnaireFieldDefinition: Codable, Equatable {
    let id: String
    let type: QuestionnaireFieldType
    let requiredLevel: RequiredLevel
    let validators: [QuestionnaireValidationRule]
    let promptHint: String
    let fallbackQuestion: String
}

struct QuestionnaireSchema: Codable, Equatable {
    let id: String
    let title: String
    let fields: [QuestionnaireFieldDefinition]

    func field(id: String) -> QuestionnaireFieldDefinition? {
        fields.first(where: { $0.id == id })
    }
}

enum QuestionnaireValue: Codable, Equatable {
    case text(String)
    case dateRange(VacationDateRange)
    case money(VacationBudgetInput)
    case integer(Int)
    case stringList([String])

    private enum CodingKeys: String, CodingKey {
        case kind
        case text
        case dateRange
        case money
        case integer
        case stringList
    }

    private enum Kind: String, Codable {
        case text
        case dateRange
        case money
        case integer
        case stringList
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .dateRange:
            self = .dateRange(try container.decode(VacationDateRange.self, forKey: .dateRange))
        case .money:
            self = .money(try container.decode(VacationBudgetInput.self, forKey: .money))
        case .integer:
            self = .integer(try container.decode(Int.self, forKey: .integer))
        case .stringList:
            self = .stringList(try container.decode([String].self, forKey: .stringList))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(value):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(value, forKey: .text)
        case let .dateRange(value):
            try container.encode(Kind.dateRange, forKey: .kind)
            try container.encode(value, forKey: .dateRange)
        case let .money(value):
            try container.encode(Kind.money, forKey: .kind)
            try container.encode(value, forKey: .money)
        case let .integer(value):
            try container.encode(Kind.integer, forKey: .kind)
            try container.encode(value, forKey: .integer)
        case let .stringList(value):
            try container.encode(Kind.stringList, forKey: .kind)
            try container.encode(value, forKey: .stringList)
        }
    }
}

enum QuestionnaireAnswerSource: String, Codable, Equatable {
    case llmExtraction
    case chat
    case form
}

struct QuestionnaireFieldAnswer: Codable, Equatable {
    let value: QuestionnaireValue
    let confidence: Double
    let source: QuestionnaireAnswerSource
    let updatedAt: Date
}

struct QuestionPrompt: Codable, Equatable {
    let fieldID: String?
    let text: String
    let suggestions: [String]
    let isFallback: Bool
}

struct QuestionnaireInteraction: Codable, Equatable {
    let question: QuestionPrompt
    let userAnswer: String
    let createdAt: Date
}

struct QuestionnaireState: Codable, Equatable {
    var answers: [String: QuestionnaireFieldAnswer]
    var missingHard: [String]
    var missingSoft: [String]
    var history: [QuestionnaireInteraction]

    static let empty = QuestionnaireState(
        answers: [:],
        missingHard: [],
        missingSoft: [],
        history: []
    )
}

struct QuestionnaireFieldExtraction: Codable, Equatable {
    let fieldID: String
    let value: QuestionnaireValue
    let confidence: Double
    let rationale: String?
}

enum QuestionnaireWarningCode: String, Codable, Equatable {
    case invalidJSON = "invalid_json"
    case invalidType = "invalid_type"
    case outOfRange = "out_of_range"
    case ambiguous = "ambiguous"
    case notExtracted = "not_extracted"
    case llmError = "llm_error"
}

struct QuestionnaireExtractionWarning: Codable, Equatable {
    let code: QuestionnaireWarningCode
    let fieldID: String?
    let message: String
}

struct QuestionnaireExtractionResult: Codable, Equatable {
    let fields: [QuestionnaireFieldExtraction]
    let warnings: [QuestionnaireExtractionWarning]
}

enum QuestionnaireNextAction: Equatable {
    case askNextQuestion(fieldID: String, warning: String?)
    case warnSoftMissing(message: String, suggestedFieldID: String?)
    case proceed
}

struct QuestionnaireProcessingResult: Equatable {
    let state: QuestionnaireState
    let updatedSlots: VacationSlots
    let validationErrors: [String]
    let action: QuestionnaireNextAction
}

enum QuestionnaireProgress: Equatable {
    case collectingHard(missing: [String])
    case collectingSoft(missing: [String])
    case complete
}

struct VacationQuestionnaireSchemaAdapter {
    static let destinationFieldID = "destination"
    static let datesFieldID = "dates"
    static let budgetFieldID = "budget"
    static let styleFieldID = "travel_style"
    static let interestsFieldID = "interests"
    static let constraintsFieldID = "constraints"

    static let schema = QuestionnaireSchema(
        id: "vacation.v1",
        title: "Vacation Planner Questionnaire",
        fields: [
            QuestionnaireFieldDefinition(
                id: destinationFieldID,
                type: .text,
                requiredLevel: .hard,
                validators: [.nonEmptyText],
                promptHint: "Направление поездки или стиль отдыха.",
                fallbackQuestion: "Куда вы хотите поехать? Если без конкретной страны, укажите предпочитаемый стиль отдыха."
            ),
            QuestionnaireFieldDefinition(
                id: datesFieldID,
                type: .dateRange,
                requiredLevel: .hard,
                validators: [.validDateRange],
                promptHint: "Даты начала и окончания поездки в формате YYYY-MM-DD.",
                fallbackQuestion: "Укажите дату начала и дату окончания поездки в формате YYYY-MM-DD."
            ),
            QuestionnaireFieldDefinition(
                id: budgetFieldID,
                type: .money,
                requiredLevel: .hard,
                validators: [.positiveMoneyAmount],
                promptHint: "Общий бюджет и валюта поездки.",
                fallbackQuestion: "Какой у вас общий бюджет на поездку и в какой валюте?"
            ),
            QuestionnaireFieldDefinition(
                id: styleFieldID,
                type: .text,
                requiredLevel: .soft,
                validators: [.nonEmptyText],
                promptHint: "Предпочитаемый стиль: пляж, экскурсии, активный отдых и т.д.",
                fallbackQuestion: "Какой стиль отдыха вам ближе: спокойный, экскурсионный, активный?"
            ),
            QuestionnaireFieldDefinition(
                id: interestsFieldID,
                type: .stringList,
                requiredLevel: .soft,
                validators: [.nonEmptyList],
                promptHint: "Интересы пользователя: еда, музеи, природа и т.д.",
                fallbackQuestion: "Что вам интересно в поездке: еда, музеи, природа, шопинг, ночная жизнь?"
            ),
            QuestionnaireFieldDefinition(
                id: constraintsFieldID,
                type: .stringList,
                requiredLevel: .soft,
                validators: [],
                promptHint: "Ограничения: дети, визы, здоровье, стыковки, темп.",
                fallbackQuestion: "Есть ли ограничения: визы, здоровье, дети, длительные переезды, ранние вылеты?"
            ),
        ]
    )

    static func makeInitialState(from slots: VacationSlots) -> QuestionnaireState {
        var answers: [String: QuestionnaireFieldAnswer] = [:]
        let now = Date()
        if let destination = slots.destination {
            answers[destinationFieldID] = QuestionnaireFieldAnswer(
                value: .text(destination),
                confidence: 1.0,
                source: .chat,
                updatedAt: now
            )
        }
        if let range = slots.dateRange {
            answers[datesFieldID] = QuestionnaireFieldAnswer(
                value: .dateRange(range),
                confidence: 1.0,
                source: .chat,
                updatedAt: now
            )
        }
        if let budget = slots.budget {
            answers[budgetFieldID] = QuestionnaireFieldAnswer(
                value: .money(budget),
                confidence: 1.0,
                source: .chat,
                updatedAt: now
            )
        }
        if let style = slots.travelStyle {
            answers[styleFieldID] = QuestionnaireFieldAnswer(
                value: .text(style),
                confidence: 1.0,
                source: .chat,
                updatedAt: now
            )
        }
        if !slots.interests.isEmpty {
            answers[interestsFieldID] = QuestionnaireFieldAnswer(
                value: .stringList(slots.interests),
                confidence: 1.0,
                source: .chat,
                updatedAt: now
            )
        }
        if !slots.constraints.isEmpty {
            answers[constraintsFieldID] = QuestionnaireFieldAnswer(
                value: .stringList(slots.constraints),
                confidence: 1.0,
                source: .chat,
                updatedAt: now
            )
        }
        return QuestionnaireState(answers: answers, missingHard: [], missingSoft: [], history: [])
    }

    static func mergeSlots(
        current: VacationSlots,
        updates: [String: QuestionnaireFieldAnswer]
    ) -> VacationSlots {
        var next = current
        for (fieldID, answer) in updates {
            switch (fieldID, answer.value) {
            case (destinationFieldID, let .text(value)):
                next.destination = value
            case (datesFieldID, let .dateRange(value)):
                next.dateRange = value
            case (budgetFieldID, let .money(value)):
                next.budget = value
            case (styleFieldID, let .text(value)):
                next.travelStyle = value
            case (interestsFieldID, let .stringList(value)):
                next.interests = next.interests.mergingUnique(with: value)
            case (constraintsFieldID, let .stringList(value)):
                next.constraints = next.constraints.mergingUnique(with: value)
            default:
                continue
            }
        }
        return next
    }
}

struct VacationOption: Codable, Equatable {
    let title: String
    let summary: String
    let estimatedCost: Double
}

struct VacationItineraryDay: Codable, Equatable {
    let dayIndex: Int
    let title: String
    let activities: [String]
}

struct VacationItinerary: Codable, Equatable {
    let days: [VacationItineraryDay]
    let notes: String
}

struct VacationBudgetBreakdown: Codable, Equatable {
    let transport: Double
    let accommodation: Double
    let food: Double
    let activities: Double
    let buffer: Double
    let total: Double
    let currency: String
}

struct VacationPlan: Codable, Equatable {
    let sessionID: UUID
    let branchID: UUID
    let slots: VacationSlots
    let selectedOption: VacationOption?
    let itinerary: VacationItinerary
    let budget: VacationBudgetBreakdown
    let createdAt: Date
}

struct VacationPlanningContext: Codable, Equatable {
    var slots: VacationSlots
    var questionnaireState: QuestionnaireState
    var options: [VacationOption]
    var itinerary: VacationItinerary?
    var budgetBreakdown: VacationBudgetBreakdown?
    var selectedOption: VacationOption?
    var revisionCount: Int
    var itineraryBuiltAt: Date?
    var budgetReviewedAt: Date?
    var planApprovedAt: Date?
    var executionCompletedAt: Date?
    var validationPassedAt: Date?
    var lastValidationErrors: [String]
    var lastUserMessage: String?
    var finalPlan: VacationPlan?
    var isFinalPlanLocked: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        slots: VacationSlots,
        questionnaireState: QuestionnaireState,
        options: [VacationOption],
        itinerary: VacationItinerary?,
        budgetBreakdown: VacationBudgetBreakdown?,
        selectedOption: VacationOption?,
        revisionCount: Int,
        itineraryBuiltAt: Date?,
        budgetReviewedAt: Date?,
        planApprovedAt: Date?,
        executionCompletedAt: Date?,
        validationPassedAt: Date?,
        lastValidationErrors: [String],
        lastUserMessage: String?,
        finalPlan: VacationPlan?,
        isFinalPlanLocked: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.slots = slots
        self.questionnaireState = questionnaireState
        self.options = options
        self.itinerary = itinerary
        self.budgetBreakdown = budgetBreakdown
        self.selectedOption = selectedOption
        self.revisionCount = revisionCount
        self.itineraryBuiltAt = itineraryBuiltAt
        self.budgetReviewedAt = budgetReviewedAt
        self.planApprovedAt = planApprovedAt
        self.executionCompletedAt = executionCompletedAt
        self.validationPassedAt = validationPassedAt
        self.lastValidationErrors = lastValidationErrors
        self.lastUserMessage = lastUserMessage
        self.finalPlan = finalPlan
        self.isFinalPlanLocked = isFinalPlanLocked
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static let initial = VacationPlanningContext(
        slots: VacationSlots(),
        questionnaireState: .empty,
        options: [],
        itinerary: nil,
        budgetBreakdown: nil,
        selectedOption: nil,
        revisionCount: 0,
        itineraryBuiltAt: nil,
        budgetReviewedAt: nil,
        planApprovedAt: nil,
        executionCompletedAt: nil,
        validationPassedAt: nil,
        lastValidationErrors: [],
        lastUserMessage: nil,
        finalPlan: nil,
        isFinalPlanLocked: false,
        createdAt: Date(),
        updatedAt: Date()
    )

    private enum CodingKeys: String, CodingKey {
        case slots
        case questionnaireState
        case options
        case itinerary
        case budgetBreakdown
        case selectedOption
        case revisionCount
        case itineraryBuiltAt
        case budgetReviewedAt
        case planApprovedAt
        case executionCompletedAt
        case validationPassedAt
        case lastValidationErrors
        case lastUserMessage
        case finalPlan
        case isFinalPlanLocked
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slots = try container.decode(VacationSlots.self, forKey: .slots)
        questionnaireState = try container.decodeIfPresent(QuestionnaireState.self, forKey: .questionnaireState) ?? .empty
        options = try container.decode([VacationOption].self, forKey: .options)
        itinerary = try container.decodeIfPresent(VacationItinerary.self, forKey: .itinerary)
        budgetBreakdown = try container.decodeIfPresent(VacationBudgetBreakdown.self, forKey: .budgetBreakdown)
        selectedOption = try container.decodeIfPresent(VacationOption.self, forKey: .selectedOption)
        revisionCount = try container.decode(Int.self, forKey: .revisionCount)
        itineraryBuiltAt = try container.decodeIfPresent(Date.self, forKey: .itineraryBuiltAt)
        budgetReviewedAt = try container.decodeIfPresent(Date.self, forKey: .budgetReviewedAt)
        planApprovedAt = try container.decodeIfPresent(Date.self, forKey: .planApprovedAt)
        executionCompletedAt = try container.decodeIfPresent(Date.self, forKey: .executionCompletedAt)
        validationPassedAt = try container.decodeIfPresent(Date.self, forKey: .validationPassedAt)
        lastValidationErrors = try container.decode([String].self, forKey: .lastValidationErrors)
        lastUserMessage = try container.decodeIfPresent(String.self, forKey: .lastUserMessage)
        finalPlan = try container.decodeIfPresent(VacationPlan.self, forKey: .finalPlan)
        isFinalPlanLocked = try container.decode(Bool.self, forKey: .isFinalPlanLocked)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(slots, forKey: .slots)
        try container.encode(questionnaireState, forKey: .questionnaireState)
        try container.encode(options, forKey: .options)
        try container.encodeIfPresent(itinerary, forKey: .itinerary)
        try container.encodeIfPresent(budgetBreakdown, forKey: .budgetBreakdown)
        try container.encodeIfPresent(selectedOption, forKey: .selectedOption)
        try container.encode(revisionCount, forKey: .revisionCount)
        try container.encodeIfPresent(itineraryBuiltAt, forKey: .itineraryBuiltAt)
        try container.encodeIfPresent(budgetReviewedAt, forKey: .budgetReviewedAt)
        try container.encodeIfPresent(planApprovedAt, forKey: .planApprovedAt)
        try container.encodeIfPresent(executionCompletedAt, forKey: .executionCompletedAt)
        try container.encodeIfPresent(validationPassedAt, forKey: .validationPassedAt)
        try container.encode(lastValidationErrors, forKey: .lastValidationErrors)
        try container.encodeIfPresent(lastUserMessage, forKey: .lastUserMessage)
        try container.encodeIfPresent(finalPlan, forKey: .finalPlan)
        try container.encode(isFinalPlanLocked, forKey: .isFinalPlanLocked)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

struct VacationPlanningSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let sessionID: UUID
    let branchID: UUID
    let state: VacationPlanningState
    let context: VacationPlanningContext
    let updatedAt: Date

    static let schemaVersionCurrent = 2
}

enum VacationPlanningEvent {
    case started
    case userMessage(text: String, source: QuestionnaireAnswerSource)
    case questionnaireProcessed(QuestionnaireProcessingResult)
    case optionsGenerated([VacationOption])
    case itineraryGenerated(VacationItinerary)
    case budgetCalculated(VacationBudgetBreakdown)
    case planApproved
    case executionCompleted
    case validationPassed
    case validationFailed(reason: String)
    case finalizeRequested
    case revisionRequested(comment: String)
    case errorOccurred(VacationPlanningError)
}

enum VacationQuestionKey: String {
    case provideBasics
    case missingDestination
    case missingDates
    case missingBudget
    case approval
    case executeApprovedPlan
    case validateBeforeFinal
    case finalizeReady
    case retryAfterError
}

enum VacationEffect {
    case notifyUser(String)
    case askUser(questionKey: VacationQuestionKey)
    case askQuestion(fieldID: String?, warning: String?)
    case processUserAnswer(String, QuestionnaireAnswerSource)
    case generateDestinationOptions
    case generateItinerary
    case calculateBudget
    case persistSnapshot
    case emitFinalPlan
}

enum VacationPlanningError: Error {
    case invariantViolation([InvariantViolation])
    case invalidTransition(String)
    case serviceFailure(String)
}

struct VacationPlanningTransitionResult {
    let nextState: VacationPlanningState
    let nextContext: VacationPlanningContext
    let effects: [VacationEffect]
}

struct VacationPlanningTurnResult {
    let snapshot: VacationPlanningSnapshot
    let agentMessages: [String]
}

enum VacationPlanningInvariant: String, CaseIterable, Equatable, Codable {
    case dateRangeOrder
    case positiveBudget
    case positiveTravelerCount
    case nonNegativeRevision
    case awaitingPlanApprovalRequiresDestination
    case generateResultRequiresPlanApproval
    case failedRequiresReason
    case snapshotTimestampConsistency
}

struct InvariantViolation: Codable {
    let invariant: VacationPlanningInvariant
    let message: String
}

enum VacationPlanningInvariantValidator {
    static func validate(
        state: VacationPlanningState,
        context: VacationPlanningContext,
        snapshotUpdatedAt: Date
    ) -> [InvariantViolation] {
        var violations: [InvariantViolation] = []

        if let range = context.slots.dateRange, range.start > range.end {
            violations.append(
                InvariantViolation(
                    invariant: .dateRangeOrder,
                    message: "Дата начала поездки должна быть не позже даты окончания."
                )
            )
        }
        if let budget = context.slots.budget, budget.total <= 0 {
            violations.append(
                InvariantViolation(
                    invariant: .positiveBudget,
                    message: "Бюджет должен быть больше 0, если он указан."
                )
            )
        }
        if context.slots.travelerCount < 1 {
            violations.append(
                InvariantViolation(
                    invariant: .positiveTravelerCount,
                    message: "Количество путешественников должно быть не меньше 1."
                )
            )
        }
        if context.revisionCount < 0 {
            violations.append(
                InvariantViolation(
                    invariant: .nonNegativeRevision,
                    message: "Счетчик правок не может быть отрицательным."
                )
            )
        }
        if case .awaitingPlanApproval = state, context.slots.destination == nil {
            violations.append(
                InvariantViolation(
                    invariant: .awaitingPlanApprovalRequiresDestination,
                    message: "Перед подтверждением нужен валидный destination."
                )
            )
        }
        if case .generateResult = state, context.planApprovedAt == nil {
            violations.append(
                InvariantViolation(
                    invariant: .generateResultRequiresPlanApproval,
                    message: "Генерация финального плана возможна только после подтверждения пользователем."
                )
            )
        }
        if case let .failed(reason) = state, reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            violations.append(
                InvariantViolation(
                    invariant: .failedRequiresReason,
                    message: "Состояние ошибки должно содержать непустую причину."
                )
            )
        }
        if snapshotUpdatedAt < context.createdAt || snapshotUpdatedAt < context.updatedAt {
            violations.append(
                InvariantViolation(
                    invariant: .snapshotTimestampConsistency,
                    message: "Временная метка snapshot должна быть не раньше меток контекста."
                )
            )
        }

        return violations
    }
}

extension Array where Element == String {
    func mergingUnique(with other: [String]) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for value in self + other {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            if seen.insert(normalized.lowercased()).inserted {
                result.append(normalized)
            }
        }
        return result
    }
}

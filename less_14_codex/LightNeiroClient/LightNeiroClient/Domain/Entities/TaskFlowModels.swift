import Foundation

enum VacationPlanningState: Equatable, Codable {
    case idle
    case collectingRequirements
    case clarifyingMissingData
    case generatingOptions
    case buildingItinerary
    case budgetReview
    case awaitingApproval
    case completed
    case failed(reason: String)

    var title: String {
        switch self {
        case .idle:
            return "Ожидание"
        case .collectingRequirements:
            return "Сбор требований"
        case .clarifyingMissingData:
            return "Уточнение недостающих данных"
        case .generatingOptions:
            return "Генерация вариантов"
        case .buildingItinerary:
            return "Составление маршрута"
        case .budgetReview:
            return "Проверка бюджета"
        case .awaitingApproval:
            return "Ожидание подтверждения"
        case .completed:
            return "Завершено"
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
        case collectingRequirements
        case clarifyingMissingData
        case generatingOptions
        case buildingItinerary
        case budgetReview
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
        case .collectingRequirements:
            self = .collectingRequirements
        case .clarifyingMissingData:
            self = .clarifyingMissingData
        case .generatingOptions:
            self = .generatingOptions
        case .buildingItinerary:
            self = .buildingItinerary
        case .budgetReview:
            self = .budgetReview
        case .awaitingApproval:
            self = .awaitingApproval
        case .completed:
            self = .completed
        case .failed:
            self = .failed(reason: try container.decode(String.self, forKey: .reason))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .idle:
            try container.encode(Kind.idle, forKey: .kind)
        case .collectingRequirements:
            try container.encode(Kind.collectingRequirements, forKey: .kind)
        case .clarifyingMissingData:
            try container.encode(Kind.clarifyingMissingData, forKey: .kind)
        case .generatingOptions:
            try container.encode(Kind.generatingOptions, forKey: .kind)
        case .buildingItinerary:
            try container.encode(Kind.buildingItinerary, forKey: .kind)
        case .budgetReview:
            try container.encode(Kind.budgetReview, forKey: .kind)
        case .awaitingApproval:
            try container.encode(Kind.awaitingApproval, forKey: .kind)
        case .completed:
            try container.encode(Kind.completed, forKey: .kind)
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
    var options: [VacationOption]
    var itinerary: VacationItinerary?
    var budgetBreakdown: VacationBudgetBreakdown?
    var selectedOption: VacationOption?
    var revisionCount: Int
    var itineraryBuiltAt: Date?
    var budgetReviewedAt: Date?
    var lastValidationErrors: [String]
    var lastUserMessage: String?
    var finalPlan: VacationPlan?
    var isFinalPlanLocked: Bool
    var createdAt: Date
    var updatedAt: Date

    static let initial = VacationPlanningContext(
        slots: VacationSlots(),
        options: [],
        itinerary: nil,
        budgetBreakdown: nil,
        selectedOption: nil,
        revisionCount: 0,
        itineraryBuiltAt: nil,
        budgetReviewedAt: nil,
        lastValidationErrors: [],
        lastUserMessage: nil,
        finalPlan: nil,
        isFinalPlanLocked: false,
        createdAt: Date(),
        updatedAt: Date()
    )
}

struct VacationPlanningSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let sessionID: UUID
    let branchID: UUID
    let state: VacationPlanningState
    let context: VacationPlanningContext
    let updatedAt: Date

    static let schemaVersionCurrent = 1
}

enum VacationPlanningEvent {
    case started
    case userMessage(text: String)
    case slotsExtracted(VacationSlots)
    case slotsValidationFailed(errors: [String])
    case optionsGenerated([VacationOption])
    case itineraryGenerated(VacationItinerary)
    case budgetCalculated(VacationBudgetBreakdown)
    case approved
    case revisionRequested(comment: String)
    case errorOccurred(VacationPlanningError)
}

enum VacationQuestionKey: String {
    case provideBasics
    case missingDestination
    case missingDates
    case missingBudget
    case approval
    case retryAfterError
}

enum VacationEffect {
    case askUser(questionKey: VacationQuestionKey)
    case extractSlotsFromUserText(String)
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
    case completedRequiresArtifacts
    case awaitingApprovalRequiresCompletedSteps
    case buildingRequiresMinimumInput
    case generatingRequiresMinimumInput
    case failedRequiresReason
    case finalPlanImmutableWhenCompleted
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
        if case .completed = state, (context.itinerary == nil || context.budgetBreakdown == nil) {
            violations.append(
                InvariantViolation(
                    invariant: .completedRequiresArtifacts,
                    message: "Для завершения нужны маршрут и бюджет."
                )
            )
        }
        if case .awaitingApproval = state, (context.itineraryBuiltAt == nil || context.budgetReviewedAt == nil) {
            violations.append(
                InvariantViolation(
                    invariant: .awaitingApprovalRequiresCompletedSteps,
                    message: "Перед подтверждением должны быть готовы маршрут и проверка бюджета."
                )
            )
        }
        if case .buildingItinerary = state, !context.slots.hasMinimumInput {
            violations.append(
                InvariantViolation(
                    invariant: .buildingRequiresMinimumInput,
                    message: "Для составления маршрута нужны направление/стиль, даты и бюджет."
                )
            )
        }
        if case .generatingOptions = state, !context.slots.hasMinimumInput {
            violations.append(
                InvariantViolation(
                    invariant: .generatingRequiresMinimumInput,
                    message: "Для генерации вариантов нужны направление/стиль, даты и бюджет."
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
        if case .completed = state, (!context.isFinalPlanLocked || context.finalPlan == nil) {
            violations.append(
                InvariantViolation(
                    invariant: .finalPlanImmutableWhenCompleted,
                    message: "В завершенном состоянии итоговый план должен быть сохранен и заблокирован."
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

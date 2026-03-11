import XCTest
@testable import LightNeiroClient

final class VacationPlanningLifecycleTests: XCTestCase {
    private let sessionID = UUID()
    private let branchID = UUID()

    func testAllowedLifecycleTransitionsFollowDestinationFSM() {
        let reducer = VacationPlannerReducer()
        let idle = makeSnapshot(state: .idle, context: makeContext(destination: nil))

        let requested = reducer.reduce(snapshot: idle, event: .started)
        XCTAssertEqual(requested.nextState, .destinationRequest)

        let requestingSnapshot = makeSnapshot(state: requested.nextState, context: requested.nextContext)
        let validating = reducer.reduce(
            snapshot: requestingSnapshot,
            event: .userMessage(text: "Хочу в Италию", source: .chat)
        )
        XCTAssertEqual(validating.nextState, .validatingDestination)

        let validatingSnapshot = makeSnapshot(state: validating.nextState, context: validating.nextContext)
        let validated = reducer.reduce(
            snapshot: validatingSnapshot,
            event: .questionnaireProcessed(validDestinationResult)
        )
        XCTAssertEqual(validated.nextState, .awaitingPlanApproval)

        let approvalSnapshot = makeSnapshot(state: validated.nextState, context: validated.nextContext)
        let generating = reducer.reduce(snapshot: approvalSnapshot, event: .planApproved)
        XCTAssertEqual(generating.nextState, .generateResult)
        XCTAssertNotNil(generating.nextContext.planApprovedAt)

        let optionsSnapshot = makeSnapshot(state: generating.nextState, context: generating.nextContext)
        let optionsProcessed = reducer.reduce(snapshot: optionsSnapshot, event: .optionsGenerated([sampleOption]))
        XCTAssertEqual(optionsProcessed.nextState, .generateResult)

        let itinerarySnapshot = makeSnapshot(state: optionsProcessed.nextState, context: optionsProcessed.nextContext)
        let itineraryProcessed = reducer.reduce(snapshot: itinerarySnapshot, event: .itineraryGenerated(sampleItinerary))
        XCTAssertEqual(itineraryProcessed.nextState, .generateResult)

        let budgetSnapshot = makeSnapshot(state: itineraryProcessed.nextState, context: itineraryProcessed.nextContext)
        let finalized = reducer.reduce(snapshot: budgetSnapshot, event: .budgetCalculated(sampleBudget))
        XCTAssertEqual(finalized.nextState, .idle)
        XCTAssertNotNil(finalized.nextContext.finalPlan)
        XCTAssertTrue(finalized.nextContext.isFinalPlanLocked)
    }

    func testInvalidTransitionFromIdleIsBlockedAndStateDoesNotChange() {
        let reducer = VacationPlannerReducer()
        let snapshot = makeSnapshot(state: .idle, context: makeContext(destination: nil))

        let transition = reducer.reduce(snapshot: snapshot, event: .planApproved)

        XCTAssertEqual(transition.nextState, .idle)
        XCTAssertTrue(containsNotifyUserEffect(in: transition.effects))
    }

    func testFirstUserMessageFromIdleRequestsDestinationBeforeValidation() {
        let reducer = VacationPlannerReducer()
        let snapshot = makeSnapshot(state: .idle, context: makeContext(destination: nil))

        let transition = reducer.reduce(
            snapshot: snapshot,
            event: .userMessage(text: "Хочу в Италию", source: .chat)
        )

        XCTAssertEqual(transition.nextState, .destinationRequest)
        XCTAssertTrue(containsAskDestinationQuestionEffect(in: transition.effects))
        XCTAssertFalse(containsProcessUserAnswerEffect(in: transition.effects))
    }

    func testValidationFailureReturnsToDestinationRequest() {
        let reducer = VacationPlannerReducer()
        let snapshot = makeSnapshot(
            state: .validatingDestination,
            context: makeContext(destination: nil)
        )

        let transition = reducer.reduce(snapshot: snapshot, event: .questionnaireProcessed(invalidDestinationResult))

        XCTAssertEqual(transition.nextState, .destinationRequest)
    }

    func testRevisionFromAwaitingApprovalReturnsToDestinationRequest() {
        let reducer = VacationPlannerReducer()
        let snapshot = makeSnapshot(
            state: .awaitingPlanApproval,
            context: makeContext(destination: "Italy")
        )

        let transition = reducer.reduce(snapshot: snapshot, event: .revisionRequested(comment: "Хочу другое направление"))

        XCTAssertEqual(transition.nextState, .destinationRequest)
        XCTAssertNil(transition.nextContext.slots.destination)
    }

    func testInvariantViolationsAreNotCheckedOutsideValidatingDestination() {
        let reducer = VacationPlannerReducer()
        let snapshot = makeSnapshot(
            state: .idle,
            context: makeContext(destination: nil, travelerCount: 0)
        )

        let transition = reducer.reduce(snapshot: snapshot, event: .started)

        XCTAssertEqual(transition.nextState, .destinationRequest)
    }

    func testInvariantViolationsAreCheckedOnValidatingDestination() {
        let reducer = VacationPlannerReducer()
        let snapshot = makeSnapshot(
            state: .validatingDestination,
            context: makeContext(destination: "Italy", travelerCount: 0)
        )

        let transition = reducer.reduce(snapshot: snapshot, event: .questionnaireProcessed(validDestinationResult))

        guard case let .failed(reason) = transition.nextState else {
            XCTFail("Expected failed state on invariant violation")
            return
        }
        XCTAssertTrue(reason.contains("Количество путешественников"))
    }

    func testPauseResumeKeepsLifecycleAndAllowsContinuation() async throws {
        let stateRepository = MockVacationPlanningStateRepository()
        let planRepository = MockVacationPlanRepository()
        let settingsRepository = MockSettingsRepository()

        let seededSnapshot = makeSnapshot(
            state: .awaitingPlanApproval,
            context: makeContext(
                destination: "Barcelona"
            )
        )
        try await stateRepository.saveSnapshot(seededSnapshot)

        let firstOrchestrator = makeOrchestrator(
            stateRepository: stateRepository,
            planRepository: planRepository,
            settingsRepository: settingsRepository
        )
        let approved = try await firstOrchestrator.process(
            sessionID: sessionID,
            branchID: branchID,
            initialEvent: .planApproved
        )
        XCTAssertEqual(approved.snapshot.state, .idle)
        XCTAssertNotNil(approved.snapshot.context.finalPlan)
        XCTAssertTrue(approved.agentMessages.contains(where: { $0.contains("MCP open-weather: запрашиваю актуальную погоду") }))
        XCTAssertTrue(approved.agentMessages.contains(where: { $0.contains("Финальный план отпуска:") }))
        XCTAssertTrue(approved.agentMessages.contains(where: { $0.contains("Погода (MCP):") }))
    }

    func testApprovalMessageContainsCollectedUserData() async throws {
        let stateRepository = MockVacationPlanningStateRepository()
        let planRepository = MockVacationPlanRepository()
        let settingsRepository = MockSettingsRepository()

        let validatingSnapshot = makeSnapshot(
            state: .validatingDestination,
            context: makeContext(destination: nil)
        )
        try await stateRepository.saveSnapshot(validatingSnapshot)

        let orchestrator = makeOrchestrator(
            stateRepository: stateRepository,
            planRepository: planRepository,
            settingsRepository: settingsRepository
        )

        let result = try await orchestrator.process(
            sessionID: sessionID,
            branchID: branchID,
            initialEvent: .questionnaireProcessed(validDestinationResult)
        )

        XCTAssertEqual(result.snapshot.state, .awaitingPlanApproval)
        let approvalMessage = result.agentMessages.last(where: { $0.contains("Подтвердите план:") })
        XCTAssertNotNil(approvalMessage)
        XCTAssertTrue(approvalMessage?.contains("destination: Italy") == true)
        XCTAssertTrue(approvalMessage?.contains("budget: 1000.0 USD") == true)
        XCTAssertTrue(approvalMessage?.contains("travelers: 2") == true)
    }

    func testFinalizeUseCaseRejectsWhenFinalPlanNotLocked() async throws {
        let stateRepository = MockVacationPlanningStateRepository()
        let planRepository = MockVacationPlanRepository()
        let useCase = FinalizeVacationPlanUseCase(stateRepository: stateRepository, planRepository: planRepository)

        let snapshot = makeSnapshot(
            state: .generateResult,
            context: makeContext(
                destination: "Barcelona",
                itinerary: sampleItinerary,
                itineraryBuiltAt: Date(),
                budgetBreakdown: sampleBudget,
                budgetReviewedAt: Date(),
                planApprovedAt: Date(),
                isFinalPlanLocked: false
            )
        )
        try await stateRepository.saveSnapshot(snapshot)

        do {
            _ = try await useCase.execute(sessionID: sessionID, branchID: branchID)
            XCTFail("Expected invalid transition error")
        } catch let error as VacationPlanningError {
            guard case .invalidTransition = error else {
                XCTFail("Expected invalidTransition, got \(error)")
                return
            }
        }
    }

    func testFinalizeUseCaseSucceedsAfterGenerateResultCompleted() async throws {
        let stateRepository = MockVacationPlanningStateRepository()
        let planRepository = MockVacationPlanRepository()
        let useCase = FinalizeVacationPlanUseCase(stateRepository: stateRepository, planRepository: planRepository)

        let now = Date()
        let finalPlan = VacationPlan(
            sessionID: sessionID,
            branchID: branchID,
            slots: VacationSlots(
                destination: "Barcelona",
                dateRange: VacationDateRange(start: now, end: now.addingTimeInterval(86_400)),
                budget: VacationBudgetInput(total: 1000, currency: "USD")
            ),
            selectedOption: nil,
            itinerary: sampleItinerary,
            budget: sampleBudget,
            weatherSummary: nil,
            createdAt: now
        )

        let snapshot = makeSnapshot(
            state: .idle,
            context: makeContext(
                destination: "Barcelona",
                itinerary: sampleItinerary,
                itineraryBuiltAt: now,
                budgetBreakdown: sampleBudget,
                budgetReviewedAt: now,
                planApprovedAt: now,
                finalPlan: finalPlan,
                isFinalPlanLocked: true
            )
        )
        try await stateRepository.saveSnapshot(snapshot)

        let persisted = try await useCase.execute(sessionID: sessionID, branchID: branchID)
        XCTAssertEqual(persisted, finalPlan)
    }

    private func makeOrchestrator(
        stateRepository: VacationPlanningStateRepositoryProtocol,
        planRepository: VacationPlanRepositoryProtocol,
        settingsRepository: SettingsRepositoryProtocol
    ) -> VacationPlanningOrchestrator {
        VacationPlanningOrchestrator(
            stateRepository: stateRepository,
            planRepository: planRepository,
            settingsRepository: settingsRepository,
            reducer: VacationPlannerReducer(),
            processUserAnswerUseCase: ProcessUserAnswerUseCase(answerExtractionService: MockAnswerExtractionService()),
            questionGenerationService: MockQuestionGenerationService(),
            questionnaireSchema: VacationQuestionnaireSchemaAdapter.schema,
            optionGenerationService: MockVacationOptionGenerationService(),
            itineraryService: MockVacationItineraryService(),
            budgetEstimator: MockVacationBudgetEstimator(),
            mcpWeatherService: StubMCPWeatherService()
        )
    }

    private func makeSnapshot(
        state: VacationPlanningState,
        context: VacationPlanningContext
    ) -> VacationPlanningSnapshot {
        VacationPlanningSnapshot(
            schemaVersion: VacationPlanningSnapshot.schemaVersionCurrent,
            sessionID: sessionID,
            branchID: branchID,
            state: state,
            context: context,
            updatedAt: Date()
        )
    }

    private func makeContext(
        destination: String? = "Barcelona",
        travelerCount: Int = 2,
        itinerary: VacationItinerary? = nil,
        itineraryBuiltAt: Date? = nil,
        budgetBreakdown: VacationBudgetBreakdown? = nil,
        budgetReviewedAt: Date? = nil,
        planApprovedAt: Date? = nil,
        executionCompletedAt: Date? = nil,
        validationPassedAt: Date? = nil,
        finalPlan: VacationPlan? = nil,
        isFinalPlanLocked: Bool = false
    ) -> VacationPlanningContext {
        VacationPlanningContext(
            slots: VacationSlots(
                destination: destination,
                dateRange: VacationDateRange(start: Date(), end: Date().addingTimeInterval(86_400)),
                budget: VacationBudgetInput(total: 1000, currency: "USD"),
                travelerCount: travelerCount,
                travelStyle: "city",
                interests: ["food"],
                constraints: []
            ),
            questionnaireState: .empty,
            options: [],
            itinerary: itinerary,
            budgetBreakdown: budgetBreakdown,
            selectedOption: nil,
            revisionCount: 0,
            itineraryBuiltAt: itineraryBuiltAt,
            budgetReviewedAt: budgetReviewedAt,
            planApprovedAt: planApprovedAt,
            executionCompletedAt: executionCompletedAt,
            validationPassedAt: validationPassedAt,
            lastValidationErrors: [],
            lastUserMessage: nil,
            finalPlan: finalPlan,
            isFinalPlanLocked: isFinalPlanLocked,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func containsNotifyUserEffect(in effects: [VacationEffect]) -> Bool {
        effects.contains { effect in
            if case .notifyUser = effect {
                return true
            }
            return false
        }
    }

    private func containsAskDestinationQuestionEffect(in effects: [VacationEffect]) -> Bool {
        effects.contains { effect in
            guard case let .askQuestion(fieldID, _) = effect else { return false }
            return fieldID == VacationQuestionnaireSchemaAdapter.destinationFieldID
        }
    }

    private func containsProcessUserAnswerEffect(in effects: [VacationEffect]) -> Bool {
        effects.contains { effect in
            if case .processUserAnswer = effect {
                return true
            }
            return false
        }
    }

    private var sampleItinerary: VacationItinerary {
        VacationItinerary(
            days: [VacationItineraryDay(dayIndex: 1, title: "Arrival", activities: ["Check-in"])],
            notes: "Sample"
        )
    }

    private var sampleBudget: VacationBudgetBreakdown {
        VacationBudgetBreakdown(
            transport: 300,
            accommodation: 300,
            food: 200,
            activities: 150,
            buffer: 50,
            total: 1000,
            currency: "USD"
        )
    }

    private var sampleOption: VacationOption {
        VacationOption(
            title: "Barcelona Comfort",
            summary: "Базовый вариант отдыха",
            estimatedCost: 1200
        )
    }

    private var validDestinationResult: QuestionnaireProcessingResult {
        QuestionnaireProcessingResult(
            state: .empty,
            updatedSlots: VacationSlots(
                destination: "Italy",
                dateRange: VacationDateRange(start: Date(), end: Date().addingTimeInterval(86_400)),
                budget: VacationBudgetInput(total: 1000, currency: "USD"),
                travelerCount: 2,
                travelStyle: "city",
                interests: ["food"],
                constraints: []
            ),
            validationErrors: [],
            action: .proceed
        )
    }

    private var invalidDestinationResult: QuestionnaireProcessingResult {
        QuestionnaireProcessingResult(
            state: .empty,
            updatedSlots: VacationSlots(
                destination: nil,
                dateRange: VacationDateRange(start: Date(), end: Date().addingTimeInterval(86_400)),
                budget: VacationBudgetInput(total: 1000, currency: "USD"),
                travelerCount: 2,
                travelStyle: "city",
                interests: ["food"],
                constraints: []
            ),
            validationErrors: ["destination missing"],
            action: .askNextQuestion(fieldID: VacationQuestionnaireSchemaAdapter.destinationFieldID, warning: "Уточните destination")
        )
    }

    private struct StubMCPWeatherService: MCPWeatherServiceProtocol {
        func fetchCurrentWeather(
            serverURL _: URL,
            city: String,
            units _: String,
            language _: String?
        ) async throws -> String {
            "Current weather for \(city), ES:\n- Conditions: clear sky (Clear)\n- Temperature: 22.5°C"
        }
    }
}

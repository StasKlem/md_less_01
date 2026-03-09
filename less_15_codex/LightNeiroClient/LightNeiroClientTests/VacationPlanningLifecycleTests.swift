import XCTest
@testable import LightNeiroClient

final class VacationPlanningLifecycleTests: XCTestCase {
    private let sessionID = UUID()
    private let branchID = UUID()

    func testAllowedLifecycleTransitionsAreStrictlySequential() {
        let reducer = VacationPlannerReducer()

        let budget = VacationBudgetBreakdown(
            transport: 300,
            accommodation: 300,
            food: 200,
            activities: 150,
            buffer: 50,
            total: 1000,
            currency: "USD"
        )

        let initial = makeSnapshot(
            state: .budgetReview,
            context: makeContext(
                itinerary: sampleItinerary,
                itineraryBuiltAt: Date(),
                budgetBreakdown: nil,
                budgetReviewedAt: nil
            )
        )

        let awaiting = reducer.reduce(snapshot: initial, event: .budgetCalculated(budget))
        XCTAssertEqual(awaiting.nextState, .awaitingPlanApproval)

        let approvedSnapshot = makeSnapshot(state: awaiting.nextState, context: awaiting.nextContext)
        let approved = reducer.reduce(snapshot: approvedSnapshot, event: .planApproved)
        XCTAssertEqual(approved.nextState, .approvedForExecution)
        XCTAssertNotNil(approved.nextContext.planApprovedAt)

        let executedSnapshot = makeSnapshot(state: approved.nextState, context: approved.nextContext)
        let executed = reducer.reduce(snapshot: executedSnapshot, event: .executionCompleted)
        XCTAssertEqual(executed.nextState, .validatingResult)
        XCTAssertNotNil(executed.nextContext.executionCompletedAt)

        let validatingSnapshot = makeSnapshot(state: executed.nextState, context: executed.nextContext)
        let validated = reducer.reduce(snapshot: validatingSnapshot, event: .validationPassed)
        XCTAssertEqual(validated.nextState, .validatingResult)
        XCTAssertNotNil(validated.nextContext.validationPassedAt)

        let finalizingSnapshot = makeSnapshot(state: validated.nextState, context: validated.nextContext)
        let finalized = reducer.reduce(snapshot: finalizingSnapshot, event: .finalizeRequested)
        XCTAssertEqual(finalized.nextState, .completed)
        XCTAssertNotNil(finalized.nextContext.finalPlan)
        XCTAssertTrue(finalized.nextContext.isFinalPlanLocked)
    }

    func testExecutionBeforePlanApprovalIsBlockedAndStateDoesNotChange() {
        let reducer = VacationPlannerReducer()
        let snapshot = makeSnapshot(
            state: .awaitingPlanApproval,
            context: makeContext(
                itinerary: sampleItinerary,
                itineraryBuiltAt: Date(),
                budgetBreakdown: sampleBudget,
                budgetReviewedAt: Date()
            )
        )

        let transition = reducer.reduce(snapshot: snapshot, event: .executionCompleted)

        XCTAssertEqual(transition.nextState, .awaitingPlanApproval)
        XCTAssertTrue(containsNotifyUserEffect(in: transition.effects))
    }

    func testFinalizeBeforeValidationIsBlockedAndStateDoesNotChange() {
        let reducer = VacationPlannerReducer()
        let snapshot = makeSnapshot(
            state: .validatingResult,
            context: makeContext(
                itinerary: sampleItinerary,
                itineraryBuiltAt: Date(),
                budgetBreakdown: sampleBudget,
                budgetReviewedAt: Date(),
                planApprovedAt: Date(),
                executionCompletedAt: Date(),
                validationPassedAt: nil
            )
        )

        let transition = reducer.reduce(snapshot: snapshot, event: .finalizeRequested)

        XCTAssertEqual(transition.nextState, .validatingResult)
        XCTAssertTrue(containsNotifyUserEffect(in: transition.effects))
    }

    func testPauseResumeKeepsLifecycleAndAllowsContinuation() async throws {
        let stateRepository = MockVacationPlanningStateRepository()
        let planRepository = MockVacationPlanRepository()
        let settingsRepository = MockSettingsRepository()

        let seededSnapshot = makeSnapshot(
            state: .awaitingPlanApproval,
            context: makeContext(
                itinerary: sampleItinerary,
                itineraryBuiltAt: Date(),
                budgetBreakdown: sampleBudget,
                budgetReviewedAt: Date()
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
        XCTAssertEqual(approved.snapshot.state, .approvedForExecution)

        let resumedOrchestrator = makeOrchestrator(
            stateRepository: stateRepository,
            planRepository: planRepository,
            settingsRepository: settingsRepository
        )
        let resumed = try await resumedOrchestrator.process(
            sessionID: sessionID,
            branchID: branchID,
            initialEvent: .executionCompleted
        )
        XCTAssertEqual(resumed.snapshot.state, .validatingResult)
    }

    func testFinalizeUseCaseRejectsWhenValidationNotPassed() async throws {
        let stateRepository = MockVacationPlanningStateRepository()
        let planRepository = MockVacationPlanRepository()
        let useCase = FinalizeVacationPlanUseCase(stateRepository: stateRepository, planRepository: planRepository)

        let snapshot = makeSnapshot(
            state: .validatingResult,
            context: makeContext(
                itinerary: sampleItinerary,
                itineraryBuiltAt: Date(),
                budgetBreakdown: sampleBudget,
                budgetReviewedAt: Date(),
                planApprovedAt: Date(),
                executionCompletedAt: Date(),
                validationPassedAt: nil
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

    func testFinalizeUseCaseSucceedsAfterCompletedWithValidation() async throws {
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
            createdAt: now
        )

        let snapshot = makeSnapshot(
            state: .completed,
            context: makeContext(
                itinerary: sampleItinerary,
                itineraryBuiltAt: now,
                budgetBreakdown: sampleBudget,
                budgetReviewedAt: now,
                planApprovedAt: now,
                executionCompletedAt: now,
                validationPassedAt: now,
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
            budgetEstimator: MockVacationBudgetEstimator()
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
                destination: "Barcelona",
                dateRange: VacationDateRange(start: Date(), end: Date().addingTimeInterval(86_400)),
                budget: VacationBudgetInput(total: 1000, currency: "USD"),
                travelerCount: 2,
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
}

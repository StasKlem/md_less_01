import Foundation

enum AgentStage: String, Codable, CaseIterable, Equatable {
    case planning
    case execution
    case validation
    case done
}

enum AgentExpectedAction: String, Codable, Equatable {
    case none
    case awaitContinue = "await_continue"
    case awaitClarification = "await_clarification"
    case awaitConfirmation = "await_confirmation"
    case awaitInput = "await_input"
}

struct TaskProgressState: Codable, Equatable {
    let stage: AgentStage
    let step: Int
    let expectedAction: AgentExpectedAction
    let updatedAt: Date

    static func initial(now: Date = Date()) -> TaskProgressState {
        TaskProgressState(
            stage: .planning,
            step: 1,
            expectedAction: .awaitInput,
            updatedAt: now
        )
    }
}

enum DoneTransitionMode: String, Codable, CaseIterable, Equatable {
    case auto
    case manualCommand

    var title: String {
        switch self {
        case .auto:
            return "Авто"
        case .manualCommand:
            return "Только по команде"
        }
    }
}

struct AgentFlowSettings: Codable, Equatable {
    var doneTransitionMode: DoneTransitionMode
    var confirmCommand: String

    static let `default` = AgentFlowSettings(
        doneTransitionMode: .manualCommand,
        confirmCommand: "ок"
    )

    var normalizedConfirmCommand: String {
        let trimmed = confirmCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AgentFlowSettings.default.confirmCommand : trimmed.lowercased()
    }
}

struct StageArtifact: Identifiable, Codable, Equatable {
    let id: UUID
    let branchID: UUID
    let stage: AgentStage
    let step: Int
    let content: String
    let createdAt: Date
    let sourceMessageIDs: [UUID]

    init(
        id: UUID = UUID(),
        branchID: UUID,
        stage: AgentStage,
        step: Int,
        content: String,
        createdAt: Date = Date(),
        sourceMessageIDs: [UUID]
    ) {
        self.id = id
        self.branchID = branchID
        self.stage = stage
        self.step = step
        self.content = content
        self.createdAt = createdAt
        self.sourceMessageIDs = sourceMessageIDs
    }
}

enum TaskFlowUserAction: String, Codable, Equatable {
    case continueAction = "continue"
    case confirm = "confirm"
}

enum TaskFlowEvent: Equatable {
    case userContinue
    case userConfirm
    case userClarification
}

enum TaskFlowAvailableAction: String, Codable, CaseIterable, Equatable {
    case continueAction = "continue"
    case confirm

    var title: String {
        switch self {
        case .continueAction:
            return "Продолжить"
        case .confirm:
            return "Подтвердить"
        }
    }
}

struct TaskFlowSnapshot: Equatable {
    let state: TaskProgressState
    let availableActions: [TaskFlowAvailableAction]
}

struct TaskFlowOutput: Equatable {
    let state: TaskProgressState
    let artifact: StageArtifact
    let availableActions: [TaskFlowAvailableAction]
}

import Foundation

struct ShortTermMemorySnapshot: Codable, Equatable {
    let messages: [ChatMessage]
    let windowSize: Int
    let updatedAt: Date
}

struct TaskStateMemory: Equatable {
    let goal: String?
    let clarifiedFacts: [String]
    let constraints: [String]
    let terms: [String]
    let updatedAt: Date

    var isEmpty: Bool {
        goal == nil && clarifiedFacts.isEmpty && constraints.isEmpty && terms.isEmpty
    }
}

enum WorkingMemoryStatus: String, Codable, Equatable {
    case active
    case resolved
    case discarded
}

struct WorkingMemoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    let taskID: String
    let key: String
    let value: String
    let status: WorkingMemoryStatus
    let confidence: Double
    let updatedAt: Date
}

enum LongTermMemoryNamespace: String, Codable, CaseIterable, Equatable {
    case profile
    case decisions
    case knowledge
}

struct LongTermMemoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    let namespace: LongTermMemoryNamespace
    let key: String
    let value: String
    let confidence: Double
    let source: String
    let updatedAt: Date
}

struct MemoryContext: Equatable {
    let shortTermMessages: [ChatMessage]
    let taskState: TaskStateMemory?
    let workingMemory: [WorkingMemoryItem]
    let longTermMemory: [LongTermMemoryItem]

    init(
        shortTermMessages: [ChatMessage],
        taskState: TaskStateMemory? = nil,
        workingMemory: [WorkingMemoryItem],
        longTermMemory: [LongTermMemoryItem]
    ) {
        self.shortTermMessages = shortTermMessages
        self.taskState = taskState
        self.workingMemory = workingMemory
        self.longTermMemory = longTermMemory
    }
}

enum MemoryLayer: String, Equatable {
    case shortTerm = "краткосрочная"
    case working = "рабочая"
    case longTerm = "долговременная"
}

struct MemoryWriteEvent: Equatable {
    let layer: MemoryLayer
    let details: String
}

extension LongTermMemoryItem {
    init(stickyFact: StickyFact) {
        self.init(
            id: stickyFact.id,
            namespace: .knowledge,
            key: stickyFact.key,
            value: stickyFact.value,
            confidence: stickyFact.confidence,
            source: "sticky_fact_migration",
            updatedAt: stickyFact.updatedAt
        )
    }
}

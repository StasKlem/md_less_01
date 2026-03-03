import Foundation

struct ShortTermMemorySnapshot: Codable, Equatable {
    let sessionID: UUID
    let branchID: UUID
    let messages: [ChatMessage]
    let windowSize: Int
    let updatedAt: Date
}

enum WorkingMemoryStatus: String, Codable, Equatable {
    case active
    case resolved
    case discarded
}

struct WorkingMemoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    let sessionID: UUID
    let branchID: UUID
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
    let sessionID: UUID
    let namespace: LongTermMemoryNamespace
    let key: String
    let value: String
    let confidence: Double
    let source: String
    let updatedAt: Date
}

struct MemoryContext: Equatable {
    let shortTermMessages: [ChatMessage]
    let workingMemory: [WorkingMemoryItem]
    let longTermMemory: [LongTermMemoryItem]
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
            sessionID: stickyFact.sessionID,
            namespace: .knowledge,
            key: stickyFact.key,
            value: stickyFact.value,
            confidence: stickyFact.confidence,
            source: "sticky_fact_migration",
            updatedAt: stickyFact.updatedAt
        )
    }
}

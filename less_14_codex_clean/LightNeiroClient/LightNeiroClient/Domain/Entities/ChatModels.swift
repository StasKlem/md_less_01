import Foundation

enum MessageRole: String, Codable {
    case system
    case user
    case assistant
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let branchID: UUID
    let role: MessageRole
    let content: String
    let createdAt: Date
    let inputTokens: Int
    let outputTokens: Int
    let latencyMs: Int

    init(
        id: UUID = UUID(),
        branchID: UUID,
        role: MessageRole,
        content: String,
        createdAt: Date = Date(),
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        latencyMs: Int = 0
    ) {
        self.id = id
        self.branchID = branchID
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.latencyMs = latencyMs
    }
}

struct ChatCheckpoint: Identifiable, Codable, Equatable {
    let id: UUID
    let branchID: UUID
    let messageID: UUID
    let name: String
    let createdAt: Date
}

struct ChatBranch: Identifiable, Codable, Equatable {
    let id: UUID
    let sessionID: UUID
    let parentCheckpointID: UUID?
    let name: String
    let createdAt: Date
}

struct ChatSession: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var activeBranchID: UUID
    let createdAt: Date
}

struct StickyFact: Identifiable, Codable, Equatable {
    let id: UUID
    let sessionID: UUID
    let key: String
    let value: String
    let confidence: Double
    let updatedAt: Date
}

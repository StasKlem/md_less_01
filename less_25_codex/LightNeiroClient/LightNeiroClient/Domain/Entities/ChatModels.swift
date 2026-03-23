import Foundation

enum MessageRole: String, Codable {
    case system
    case user
    case assistant
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: MessageRole
    let content: String
    let createdAt: Date
    let inputTokens: Int
    let outputTokens: Int
    let latencyMs: Int

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        createdAt: Date = Date(),
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        latencyMs: Int = 0
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.latencyMs = latencyMs
    }
}

struct StickyFact: Identifiable, Codable, Equatable {
    let id: UUID
    let key: String
    let value: String
    let confidence: Double
    let updatedAt: Date
}

/// Контекст идентификаторов для legacy-модулей task-агентов.
struct ChatSession: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var activeBranchID: UUID
    let createdAt: Date
}

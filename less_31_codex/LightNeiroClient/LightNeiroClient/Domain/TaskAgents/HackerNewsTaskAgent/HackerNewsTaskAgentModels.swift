import Foundation

/// Возможные состояния task-агента Hacker News.
enum HackerNewsTaskAgentState: Equatable, Codable {
    case idle
    case running
    case failed(reason: String)

    var title: String {
        switch self {
        case .idle:
            return "Ожидание"
        case .running:
            return "Мониторинг Hacker News"
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
        case running
        case failed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .idle:
            self = .idle
        case .running:
            self = .running
        case .failed:
            self = .failed(reason: try container.decode(String.self, forKey: .reason))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .idle:
            try container.encode(Kind.idle, forKey: .kind)
        case .running:
            try container.encode(Kind.running, forKey: .kind)
        case let .failed(reason):
            try container.encode(Kind.failed, forKey: .kind)
            try container.encode(reason, forKey: .reason)
        }
    }
}

/// Структурированное представление одной статьи из Hacker News.
struct HackerNewsTaskAgentStory: Codable, Equatable {
    let storyID: Int?
    let title: String
    let author: String?
    let score: Int?
    let publishedAtUTC: String?
    let url: String?
    let rawText: String

    var shortSummary: String {
        var parts = ["\"\(title)\""]
        if let author, !author.isEmpty {
            parts.append("автор: \(author)")
        }
        if let score {
            parts.append("score: \(score)")
        }
        if let url, !url.isEmpty {
            parts.append(url)
        }
        return parts.joined(separator: ", ")
    }
}

/// Запись статьи, которая архивируется в JSON-файл.
struct HackerNewsTaskAgentArticleRecord: Codable, Equatable {
    let sessionID: UUID
    let branchID: UUID
    let requestNumber: Int
    let fetchedAt: Date
    let story: HackerNewsTaskAgentStory
}

/// Мини-история для регулярной LLM-сводки.
struct HackerNewsTaskAgentStoryDigest: Codable, Equatable {
    let requestNumber: Int
    let title: String
    let author: String?
    let url: String?
}

/// Контекст task-агента Hacker News.
struct HackerNewsTaskAgentContext: Codable, Equatable {
    var nextRequestNumber: Int
    var requestCount: Int
    var intervalSeconds: TimeInterval
    var llmSummaryEvery: Int
    var recentStories: [HackerNewsTaskAgentStoryDigest]
    var updatedAt: Date

    static let defaultIntervalSeconds: TimeInterval = 5
    static let defaultLLMSummaryEvery = 5

    static let initial = HackerNewsTaskAgentContext(
        nextRequestNumber: 1,
        requestCount: 0,
        intervalSeconds: defaultIntervalSeconds,
        llmSummaryEvery: defaultLLMSummaryEvery,
        recentStories: [],
        updatedAt: Date()
    )
}

/// Snapshot состояния task-агента Hacker News.
struct HackerNewsTaskAgentSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let sessionID: UUID
    let branchID: UUID
    let state: HackerNewsTaskAgentState
    let context: HackerNewsTaskAgentContext
    let updatedAt: Date

    static let schemaVersionCurrent = 1
}

/// Итог одного шага выполнения task-агента Hacker News.
struct HackerNewsTaskAgentTurnResult {
    let snapshot: HackerNewsTaskAgentSnapshot
    let systemMessages: [String]
}

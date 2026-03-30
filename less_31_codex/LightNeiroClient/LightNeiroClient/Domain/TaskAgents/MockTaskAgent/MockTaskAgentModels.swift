import Foundation

/// Возможные состояния мокового task-агента.
enum MockTaskAgentState: Equatable, Codable {
    case idle
    case awaitingTask
    case taskPrepared
    case failed(reason: String)

    /// Человекочитаемый заголовок состояния.
    var title: String {
        switch self {
        case .idle:
            return "Ожидание"
        case .awaitingTask:
            return "Ожидание описания задачи"
        case .taskPrepared:
            return "Черновик задачи подготовлен"
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
        case awaitingTask
        case taskPrepared
        case failed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .idle:
            self = .idle
        case .awaitingTask:
            self = .awaitingTask
        case .taskPrepared:
            self = .taskPrepared
        case .failed:
            self = .failed(reason: try container.decode(String.self, forKey: .reason))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .idle:
            try container.encode(Kind.idle, forKey: .kind)
        case .awaitingTask:
            try container.encode(Kind.awaitingTask, forKey: .kind)
        case .taskPrepared:
            try container.encode(Kind.taskPrepared, forKey: .kind)
        case let .failed(reason):
            try container.encode(Kind.failed, forKey: .kind)
            try container.encode(reason, forKey: .reason)
        }
    }
}

/// Контекст мокового task-агента.
struct MockTaskAgentContext: Codable, Equatable {
    var latestTask: String?
    var checklist: [String]
    var updatedAt: Date

    static let initial = MockTaskAgentContext(
        latestTask: nil,
        checklist: [],
        updatedAt: Date()
    )
}

/// Snapshot состояния мокового task-агента.
struct MockTaskAgentSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let sessionID: UUID
    let branchID: UUID
    let state: MockTaskAgentState
    let context: MockTaskAgentContext
    let updatedAt: Date

    static let schemaVersionCurrent = 1
}

/// Итог одного шага выполнения мокового task-агента.
struct MockTaskAgentTurnResult {
    let snapshot: MockTaskAgentSnapshot
    let agentMessages: [String]
}

/// Возможные состояния task-агента-счетчика.
enum CounterTaskAgentState: Equatable, Codable {
    case idle
    case running
    case failed(reason: String)

    /// Человекочитаемый заголовок состояния.
    var title: String {
        switch self {
        case .idle:
            return "Ожидание"
        case .running:
            return "Отправка системных сообщений"
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

/// Контекст task-агента-счетчика.
struct CounterTaskAgentContext: Codable, Equatable {
    var nextNumber: Int
    var intervalSeconds: TimeInterval
    var updatedAt: Date

    static let defaultIntervalSeconds: TimeInterval = 5

    static let initial = CounterTaskAgentContext(
        nextNumber: 1,
        intervalSeconds: defaultIntervalSeconds,
        updatedAt: Date()
    )
}

/// Snapshot состояния task-агента-счетчика.
struct CounterTaskAgentSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let sessionID: UUID
    let branchID: UUID
    let state: CounterTaskAgentState
    let context: CounterTaskAgentContext
    let updatedAt: Date

    static let schemaVersionCurrent = 1
}

/// Итог одного шага выполнения task-агента-счетчика.
struct CounterTaskAgentTurnResult {
    let snapshot: CounterTaskAgentSnapshot
    let systemMessages: [String]
}

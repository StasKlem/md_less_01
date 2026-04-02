import Foundation

/// Возможные состояния task-агента ревью незакоммиченных изменений.
enum ProjectReviewTaskState: Equatable, Codable, Sendable {
    case idle
    case collectingChanges
    case workingWithRAG
    case analyzingChanges
    case failed(reason: String)

    /// Человекочитаемый заголовок состояния.
    var title: String {
        switch self {
        case .idle:
            return "Не запущена"
        case .collectingChanges:
            return "Получение diff и изменённых файлов"
        case .workingWithRAG:
            return "Работа с RAG"
        case .analyzingChanges:
            return "Анализ изменений и генерация текста ревью"
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
        case collectingChanges
        case workingWithRAG
        case analyzingChanges
        case failed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .idle:
            self = .idle
        case .collectingChanges:
            self = .collectingChanges
        case .workingWithRAG:
            self = .workingWithRAG
        case .analyzingChanges:
            self = .analyzingChanges
        case .failed:
            self = .failed(reason: try container.decode(String.self, forKey: .reason))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .idle:
            try container.encode(Kind.idle, forKey: .kind)
        case .collectingChanges:
            try container.encode(Kind.collectingChanges, forKey: .kind)
        case .workingWithRAG:
            try container.encode(Kind.workingWithRAG, forKey: .kind)
        case .analyzingChanges:
            try container.encode(Kind.analyzingChanges, forKey: .kind)
        case let .failed(reason):
            try container.encode(Kind.failed, forKey: .kind)
            try container.encode(reason, forKey: .reason)
        }
    }
}

/// Фрагмент документации, выбранный через RAG.
struct ProjectReviewEvidence: Codable, Equatable, Sendable {
    let source: String
    let section: String?
    let content: String
}

/// Контекст review-task.
struct ProjectReviewTaskContext: Codable, Equatable, Sendable {
    var focus: String?
    var changedFiles: [String]
    var diff: String
    var evidence: [ProjectReviewEvidence]
    var reviewText: String?
    var updatedAt: Date

    static let initial = ProjectReviewTaskContext(
        focus: nil,
        changedFiles: [],
        diff: "",
        evidence: [],
        reviewText: nil,
        updatedAt: Date()
    )
}

/// Snapshot состояния review-task.
struct ProjectReviewTaskSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let sessionID: UUID
    let branchID: UUID
    let state: ProjectReviewTaskState
    let context: ProjectReviewTaskContext
    let updatedAt: Date

    static let schemaVersionCurrent = 1
}

/// Итог одного запуска review-task.
struct ProjectReviewTaskTurnResult: Sendable {
    let snapshot: ProjectReviewTaskSnapshot
    let reviewText: String
    let systemMessages: [String]
}

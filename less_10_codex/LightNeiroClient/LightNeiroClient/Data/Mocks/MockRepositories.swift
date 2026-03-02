import Foundation

actor InMemoryChatStore {
    static let shared = InMemoryChatStore()

    var sessions: [UUID: ChatSession] = [:]
    var branches: [UUID: [ChatBranch]] = [:]
    var checkpoints: [UUID: [ChatCheckpoint]] = [:]
    var messages: [UUID: [ChatMessage]] = [:]
    var facts: [UUID: [StickyFact]] = [:]
    var settings: [UUID: LLMSettings] = [:]
    var metricsBySession: [UUID: [RequestMetric]] = [:]

    private init() {}
}

struct MockChatSessionRepository: ChatSessionRepositoryProtocol {
    private let store = InMemoryChatStore.shared

    func fetchAllSessions() async throws -> [ChatSession] {
        Array(await store.sessions.values)
    }

    func fetchSession(id: UUID) async throws -> ChatSession? {
        await store.sessions[id]
    }

    func saveSession(_ session: ChatSession) async throws {
        await store.sessions.updateValue(session, forKey: session.id)
    }
}

struct MockBranchRepository: BranchRepositoryProtocol {
    private let store = InMemoryChatStore.shared

    func fetchBranches(sessionID: UUID) async throws -> [ChatBranch] {
        await store.branches[sessionID] ?? []
    }

    func saveBranch(_ branch: ChatBranch) async throws {
        var current = await store.branches[branch.sessionID] ?? []
        current.removeAll { $0.id == branch.id }
        current.append(branch)
        await store.branches.updateValue(current, forKey: branch.sessionID)
    }

    func saveCheckpoint(_ checkpoint: ChatCheckpoint) async throws {
        var current = await store.checkpoints[checkpoint.branchID] ?? []
        current.append(checkpoint)
        await store.checkpoints.updateValue(current, forKey: checkpoint.branchID)
    }
}

struct MockMessageRepository: MessageRepositoryProtocol {
    private let store = InMemoryChatStore.shared

    func fetchMessages(branchID: UUID) async throws -> [ChatMessage] {
        (await store.messages[branchID] ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    func saveMessage(_ message: ChatMessage) async throws {
        var current = await store.messages[message.branchID] ?? []
        current.append(message)
        await store.messages.updateValue(current, forKey: message.branchID)
    }
}

struct MockFactsRepository: FactsRepositoryProtocol {
    private let store = InMemoryChatStore.shared

    func fetchFacts(sessionID: UUID) async throws -> [StickyFact] {
        await store.facts[sessionID] ?? []
    }

    func upsertFacts(sessionID: UUID, facts: [StickyFact]) async throws {
        await store.facts.updateValue(facts, forKey: sessionID)
    }
}

struct MockSettingsRepository: SettingsRepositoryProtocol {
    private let store = InMemoryChatStore.shared

    func fetchSettings(sessionID: UUID) async throws -> LLMSettings {
        await store.settings[sessionID] ?? .default
    }

    func saveSettings(sessionID: UUID, settings: LLMSettings) async throws {
        await store.settings.updateValue(settings, forKey: sessionID)
    }
}

struct MockMetricsRepository: MetricsRepositoryProtocol {
    private let store = InMemoryChatStore.shared

    func appendMetric(_ metric: RequestMetric) async throws {
        let sessionID = await resolveSessionID(for: metric.branchID)
        guard let sessionID else { return }

        var current = await store.metricsBySession[sessionID] ?? []
        current.append(metric)
        await store.metricsBySession.updateValue(current, forKey: sessionID)
    }

    func fetchMetrics(sessionID: UUID) async throws -> [RequestMetric] {
        await store.metricsBySession[sessionID] ?? []
    }

    private func resolveSessionID(for branchID: UUID) async -> UUID? {
        let sessions = await store.sessions
        let branchesBySession = await store.branches

        for (sessionID, sessionBranches) in branchesBySession where sessions[sessionID] != nil {
            if sessionBranches.contains(where: { $0.id == branchID }) {
                return sessionID
            }
        }
        return nil
    }
}

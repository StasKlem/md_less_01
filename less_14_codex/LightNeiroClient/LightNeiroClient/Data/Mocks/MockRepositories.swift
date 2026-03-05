import Foundation

actor InMemoryChatStore {
    static let shared = InMemoryChatStore()

    var sessions: [UUID: ChatSession] = [:]
    var branches: [UUID: [ChatBranch]] = [:]
    var checkpoints: [UUID: [ChatCheckpoint]] = [:]
    var messages: [UUID: [ChatMessage]] = [:]
    var shortTermByBranch: [UUID: ShortTermMemorySnapshot] = [:]
    var workingByBranch: [UUID: [WorkingMemoryItem]] = [:]
    var longTermBySession: [UUID: [LongTermMemoryItem]] = [:]
    var facts: [UUID: [StickyFact]] = [:]
    var settings: [UUID: LLMSettings] = [:]
    var metricsBySession: [UUID: [RequestMetric]] = [:]
    var taskProgressByBranch: [UUID: TaskProgressState] = [:]
    var artifactsByBranch: [UUID: [StageArtifact]] = [:]

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

    func fetchCheckpoints(branchID: UUID) async throws -> [ChatCheckpoint] {
        (await store.checkpoints[branchID] ?? []).sorted { $0.createdAt < $1.createdAt }
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

struct MockShortTermMemoryRepository: ShortTermMemoryRepositoryProtocol {
    private let store = InMemoryChatStore.shared

    func fetchSnapshot(sessionID: UUID, branchID: UUID) async throws -> ShortTermMemorySnapshot? {
        let snapshot = await store.shortTermByBranch[branchID]
        guard snapshot?.sessionID == sessionID else { return nil }
        return snapshot
    }

    func saveSnapshot(_ snapshot: ShortTermMemorySnapshot) async throws {
        await store.shortTermByBranch.updateValue(snapshot, forKey: snapshot.branchID)
    }

    func clear(sessionID: UUID, branchID: UUID) async throws {
        let snapshot = await store.shortTermByBranch[branchID]
        guard snapshot?.sessionID == sessionID else { return }
        await store.shortTermByBranch.removeValue(forKey: branchID)
    }
}

struct MockWorkingMemoryRepository: WorkingMemoryRepositoryProtocol {
    private let store = InMemoryChatStore.shared

    func fetchActive(sessionID: UUID, branchID: UUID) async throws -> [WorkingMemoryItem] {
        let current = await store.workingByBranch[branchID] ?? []
        return current.filter { $0.sessionID == sessionID && $0.status == .active }
    }

    func upsert(sessionID: UUID, branchID: UUID, items: [WorkingMemoryItem]) async throws {
        var current = await store.workingByBranch[branchID] ?? []
        for item in items where item.sessionID == sessionID && item.branchID == branchID {
            current.removeAll { $0.key == item.key }
            current.append(item)
        }
        await store.workingByBranch.updateValue(current, forKey: branchID)
    }

    func resolve(sessionID: UUID, branchID: UUID, keys: [String]) async throws {
        guard !keys.isEmpty else { return }
        var current = await store.workingByBranch[branchID] ?? []
        let keySet = Set(keys)
        let now = Date()

        current = current.map { item in
            guard item.sessionID == sessionID, keySet.contains(item.key) else { return item }
            return WorkingMemoryItem(
                id: item.id,
                sessionID: item.sessionID,
                branchID: item.branchID,
                taskID: item.taskID,
                key: item.key,
                value: item.value,
                status: .resolved,
                confidence: item.confidence,
                updatedAt: now
            )
        }

        await store.workingByBranch.updateValue(current, forKey: branchID)
    }
}

struct MockLongTermMemoryRepository: LongTermMemoryRepositoryProtocol {
    private let store = InMemoryChatStore.shared

    func fetch(sessionID: UUID, namespaces: [LongTermMemoryNamespace]?) async throws -> [LongTermMemoryItem] {
        let current = await store.longTermBySession[sessionID] ?? []
        guard let namespaces, !namespaces.isEmpty else { return current }
        let namespaceSet = Set(namespaces)
        return current.filter { namespaceSet.contains($0.namespace) }
    }

    func upsert(sessionID: UUID, items: [LongTermMemoryItem]) async throws {
        var current = await store.longTermBySession[sessionID] ?? []
        for item in items where item.sessionID == sessionID {
            current.removeAll { $0.namespace == item.namespace && $0.key == item.key }
            current.append(item)
        }
        await store.longTermBySession.updateValue(current, forKey: sessionID)
    }

    func delete(sessionID: UUID, keys: [String]) async throws {
        guard !keys.isEmpty else { return }
        var current = await store.longTermBySession[sessionID] ?? []
        let keySet = Set(keys)
        current.removeAll { keySet.contains($0.key) }
        await store.longTermBySession.updateValue(current, forKey: sessionID)
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

struct MockTaskProgressRepository: TaskProgressRepositoryProtocol {
    private let store = InMemoryChatStore.shared

    func fetch(branchID: UUID) async throws -> TaskProgressState? {
        await store.taskProgressByBranch[branchID]
    }

    func save(branchID: UUID, state: TaskProgressState) async throws {
        await store.taskProgressByBranch.updateValue(state, forKey: branchID)
    }

    func reset(branchID: UUID) async throws {
        await store.taskProgressByBranch.removeValue(forKey: branchID)
    }
}

struct MockStageArtifactRepository: StageArtifactRepositoryProtocol {
    private let store = InMemoryChatStore.shared

    func fetchArtifacts(branchID: UUID) async throws -> [StageArtifact] {
        (await store.artifactsByBranch[branchID] ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    func fetchLatest(branchID: UUID, stage: AgentStage) async throws -> StageArtifact? {
        let artifacts = await store.artifactsByBranch[branchID] ?? []
        return artifacts
            .filter { $0.stage == stage }
            .sorted { $0.createdAt < $1.createdAt }
            .last
    }

    func save(_ artifact: StageArtifact) async throws {
        var current = await store.artifactsByBranch[artifact.branchID] ?? []
        current.removeAll { $0.id == artifact.id }
        current.append(artifact)
        await store.artifactsByBranch.updateValue(current, forKey: artifact.branchID)
    }

    func reset(branchID: UUID) async throws {
        await store.artifactsByBranch.removeValue(forKey: branchID)
    }
}

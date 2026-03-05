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
    var vacationSnapshots: [String: VacationPlanningSnapshot] = [:]
    var vacationPlans: [String: VacationPlan] = [:]

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

struct MockVacationPlanningStateRepository: VacationPlanningStateRepositoryProtocol {
    private let store = InMemoryChatStore.shared

    func fetchSnapshot(sessionID: UUID, branchID: UUID) async throws -> VacationPlanningSnapshot? {
        await store.vacationSnapshots[key(sessionID: sessionID, branchID: branchID)]
    }

    func saveSnapshot(_ snapshot: VacationPlanningSnapshot) async throws {
        await store.vacationSnapshots.updateValue(snapshot, forKey: key(sessionID: snapshot.sessionID, branchID: snapshot.branchID))
    }

    private func key(sessionID: UUID, branchID: UUID) -> String {
        "\(sessionID.uuidString.lowercased())::\(branchID.uuidString.lowercased())"
    }
}

struct MockVacationPlanRepository: VacationPlanRepositoryProtocol {
    private let store = InMemoryChatStore.shared

    func fetchFinalPlan(sessionID: UUID, branchID: UUID) async throws -> VacationPlan? {
        await store.vacationPlans[key(sessionID: sessionID, branchID: branchID)]
    }

    func saveFinalPlan(_ plan: VacationPlan) async throws {
        await store.vacationPlans.updateValue(plan, forKey: key(sessionID: plan.sessionID, branchID: plan.branchID))
    }

    private func key(sessionID: UUID, branchID: UUID) -> String {
        "\(sessionID.uuidString.lowercased())::\(branchID.uuidString.lowercased())"
    }
}

struct MockVacationSlotExtractionService: VacationSlotExtractionServiceProtocol {
    func extractSlots(from userText: String, current: VacationSlots) async throws -> VacationSlotsExtractionResult {
        var slots = current
        let lines = userText.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        for line in lines {
            let lower = line.lowercased()
            if lower.hasPrefix("destination:") {
                slots.destination = value(after: "destination:", in: line)
            } else if lower.hasPrefix("style:") {
                slots.travelStyle = value(after: "style:", in: line)
            } else if lower.hasPrefix("budget:") {
                if let budget = parseBudget(line) {
                    slots.budget = budget
                }
            } else if lower.hasPrefix("travelers:") || lower.hasPrefix("travellers:") {
                if let count = parseTravelers(line) {
                    slots.travelerCount = count
                }
            } else if lower.hasPrefix("dates:") {
                if let range = parseDateRange(line) {
                    slots.dateRange = range
                }
            } else if lower.hasPrefix("interests:") {
                slots.interests = slots.interests.mergingUniqueValues(with: csvValues(after: "interests:", in: line))
            } else if lower.hasPrefix("constraints:") {
                slots.constraints = slots.constraints.mergingUniqueValues(with: csvValues(after: "constraints:", in: line))
            }
        }

        let errors = missingRequiredFields(for: slots)
        return VacationSlotsExtractionResult(slots: slots, validationErrors: errors)
    }

    private func missingRequiredFields(for slots: VacationSlots) -> [String] {
        var errors: [String] = []
        if slots.destination == nil && slots.travelStyle == nil {
            errors.append("destination")
        }
        if slots.dateRange == nil {
            errors.append("dates")
        }
        if slots.budget == nil {
            errors.append("budget")
        }
        return errors
    }

    private func value(after prefix: String, in line: String) -> String? {
        let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func csvValues(after prefix: String, in line: String) -> [String] {
        guard let raw = value(after: prefix, in: line) else { return [] }
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func parseBudget(_ line: String) -> VacationBudgetInput? {
        guard let raw = value(after: "budget:", in: line) else { return nil }
        let parts = raw.split(separator: " ").map(String.init)
        let amountToken = parts.first?.filter { $0.isNumber || $0 == "." || $0 == "," } ?? ""
        let normalized = amountToken.replacingOccurrences(of: ",", with: ".")
        guard let amount = Double(normalized), amount > 0 else { return nil }
        let currency = parts.dropFirst().first?.uppercased() ?? "USD"
        return VacationBudgetInput(total: amount, currency: currency)
    }

    private func parseTravelers(_ line: String) -> Int? {
        let key = line.lowercased().hasPrefix("travellers:") ? "travellers:" : "travelers:"
        guard let raw = value(after: key, in: line) else { return nil }
        return Int(raw.filter(\.isNumber))
    }

    private func parseDateRange(_ line: String) -> VacationDateRange? {
        guard let raw = value(after: "dates:", in: line) else { return nil }
        let components = raw.split(separator: " ").map(String.init)
        guard components.count >= 3 else { return nil }
        let startString = components[0]
        let endString = components[2]
        let formatter = ISO8601DateFormatter()
        guard
            let start = formatter.date(from: "\(startString)T00:00:00Z"),
            let end = formatter.date(from: "\(endString)T00:00:00Z")
        else {
            return nil
        }
        return VacationDateRange(start: start, end: end)
    }
}

struct MockVacationOptionGenerationService: VacationOptionGenerationServiceProtocol {
    func generateOptions(context: VacationPlanningContext) async throws -> [VacationOption] {
        let destination = context.slots.destination ?? "Любое пляжное направление"
        let base = context.slots.budget?.total ?? 0
        return [
            VacationOption(
                title: "\(destination) Комфорт",
                summary: "Сбалансированный план: умеренная активность и спокойный темп.",
                estimatedCost: base * 0.9
            ),
            VacationOption(
                title: "\(destination) Исследование",
                summary: "Насыщенный маршрут с экскурсиями и локальной кухней.",
                estimatedCost: base
            ),
        ]
    }
}

struct MockVacationItineraryService: VacationItineraryServiceProtocol {
    func generateItinerary(context: VacationPlanningContext) async throws -> VacationItinerary {
        let destination = context.slots.destination ?? "месту отдыха"
        return VacationItinerary(
            days: [
                VacationItineraryDay(dayIndex: 1, title: "Прибытие", activities: ["Заселение", "Вечерняя прогулка по \(destination)"]),
                VacationItineraryDay(dayIndex: 2, title: "Исследование", activities: ["Обзорная экскурсия", "Знакомство с местной кухней"]),
                VacationItineraryDay(dayIndex: 3, title: "Свободный день", activities: ["Пляж или музей", "Покупка сувениров"]),
            ],
            notes: "Корректируйте активность по погоде и самочувствию."
        )
    }
}

struct MockVacationBudgetEstimator: VacationBudgetEstimatorProtocol {
    func estimateBudget(context: VacationPlanningContext) async throws -> VacationBudgetBreakdown {
        let total = context.slots.budget?.total ?? 0
        let currency = context.slots.budget?.currency ?? "USD"
        let transport = total * 0.3
        let accommodation = total * 0.35
        let food = total * 0.2
        let activities = total * 0.1
        let buffer = max(0, total - (transport + accommodation + food + activities))
        return VacationBudgetBreakdown(
            transport: transport,
            accommodation: accommodation,
            food: food,
            activities: activities,
            buffer: buffer,
            total: total,
            currency: currency
        )
    }
}

private extension Array where Element == String {
    func mergingUniqueValues(with other: [String]) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for value in self + other {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            if seen.insert(normalized.lowercased()).inserted {
                result.append(normalized)
            }
        }
        return result
    }
}

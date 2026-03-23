import Foundation

/// Формирует unified memory context для конкретной ветки.
final class BuildMemoryContextUseCase: BuildMemoryContextUseCaseProtocol {
    private let shortTermRepository: ShortTermMemoryRepositoryProtocol
    private let workingMemoryRepository: WorkingMemoryRepositoryProtocol
    private let longTermMemoryRepository: LongTermMemoryRepositoryProtocol
    private let messageRepository: MessageRepositoryProtocol

    private let maxLongTermItems = 12

    init(
        shortTermRepository: ShortTermMemoryRepositoryProtocol,
        workingMemoryRepository: WorkingMemoryRepositoryProtocol,
        longTermMemoryRepository: LongTermMemoryRepositoryProtocol,
        messageRepository: MessageRepositoryProtocol
    ) {
        self.shortTermRepository = shortTermRepository
        self.workingMemoryRepository = workingMemoryRepository
        self.longTermMemoryRepository = longTermMemoryRepository
        self.messageRepository = messageRepository
    }

    func execute(
        settings: LLMSettings
    ) async throws -> MemoryContext {
        let snapshot = try await shortTermRepository.fetchSnapshot()
        let nonSystemMessages = try await fetchNonSystemMessages()
        let shortTermMessages = selectShortTermMessages(
            snapshot: snapshot,
            fallbackMessages: nonSystemMessages,
            windowSize: settings.windowSize
        )

        let workingMemory = try await workingMemoryRepository.fetchActive()
        let longTermMemory = try await prioritizedLongTermMemory()

        return MemoryContext(
            shortTermMessages: shortTermMessages,
            workingMemory: workingMemory,
            longTermMemory: longTermMemory
        )
    }

    private func fetchNonSystemMessages() async throws -> [ChatMessage] {
        let branchMessages = try await messageRepository.fetchMessages()
        return branchMessages.filter { $0.role != .system }
    }

    private func selectShortTermMessages(
        snapshot: ShortTermMemorySnapshot?,
        fallbackMessages: [ChatMessage],
        windowSize: Int
    ) -> [ChatMessage] {
        let sourceMessages = snapshot?.messages ?? fallbackMessages
        return Array(sourceMessages.suffix(max(1, windowSize)))
    }

    private func prioritizedLongTermMemory() async throws -> [LongTermMemoryItem] {
        let items = try await longTermMemoryRepository.fetch(namespaces: nil)
        let namespacePriority: [LongTermMemoryNamespace: Int] = [
            .profile: 0,
            .decisions: 1,
            .knowledge: 2
        ]

        let sorted = items.sorted { lhs, rhs in
            let leftPriority = namespacePriority[lhs.namespace] ?? Int.max
            let rightPriority = namespacePriority[rhs.namespace] ?? Int.max
            if leftPriority != rightPriority {
                return leftPriority < rightPriority
            }
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }
            return lhs.updatedAt > rhs.updatedAt
        }

        return Array(sorted.prefix(maxLongTermItems))
    }
}

final class UpdateShortTermMemoryUseCase: UpdateShortTermMemoryUseCaseProtocol {
    private let messageRepository: MessageRepositoryProtocol
    private let shortTermRepository: ShortTermMemoryRepositoryProtocol

    init(
        messageRepository: MessageRepositoryProtocol,
        shortTermRepository: ShortTermMemoryRepositoryProtocol
    ) {
        self.messageRepository = messageRepository
        self.shortTermRepository = shortTermRepository
    }

    func execute(windowSize: Int) async throws -> MemoryWriteEvent? {
        let previous = try await shortTermRepository.fetchSnapshot()
        let allMessages = try await messageRepository.fetchMessages()
            .filter { $0.role != .system }

        let normalizedWindowSize = max(1, windowSize)
        let currentMessages = Array(allMessages.suffix(normalizedWindowSize))
        let snapshot = ShortTermMemorySnapshot(
            messages: currentMessages,
            windowSize: normalizedWindowSize,
            updatedAt: Date()
        )
        try await shortTermRepository.saveSnapshot(snapshot)

        let oldMessageIDs = previous?.messages.map(\.id) ?? []
        let newMessageIDs = currentMessages.map(\.id)
        guard oldMessageIDs != newMessageIDs else { return nil }

        let oldIDSet = Set(oldMessageIDs)
        let addedMessages = currentMessages.filter { !oldIDSet.contains($0.id) }
        let detailsSource = addedMessages.isEmpty ? currentMessages : addedMessages
        let details = detailsSource
            .map { message in
                "\(message.role.rawValue): \(normalizeMemoryText(message.content))"
            }
            .joined(separator: " | ")

        return MemoryWriteEvent(
            layer: .shortTerm,
            details: "сохранено: \(details)"
        )
    }
}

final class UpdateWorkingMemoryUseCase: UpdateWorkingMemoryUseCaseProtocol {
    private let workingMemoryRepository: WorkingMemoryRepositoryProtocol

    init(workingMemoryRepository: WorkingMemoryRepositoryProtocol) {
        self.workingMemoryRepository = workingMemoryRepository
    }

    func execute(
        latestUserMessage: String,
        latestAssistantMessage: String?
    ) async throws -> [MemoryWriteEvent] {
        let userText = latestUserMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty else { return [] }

        let active = try await workingMemoryRepository.fetchActive()
        let extracted = extractCandidates(from: userText, assistantText: latestAssistantMessage ?? "")
        let mergeResult = merge(active: active, with: extracted)
        let merged = mergeResult.items
        if !merged.isEmpty {
            try await workingMemoryRepository.upsert(items: merged)
        }

        let resolvedKeys = resolveKeys(from: userText, assistantText: latestAssistantMessage ?? "")
        if !resolvedKeys.isEmpty {
            try await workingMemoryRepository.resolve(keys: resolvedKeys)
        }

        guard !mergeResult.changedEntries.isEmpty else { return [] }
        let entries = mergeResult.changedEntries.sorted().joined(separator: " | ")
        return [MemoryWriteEvent(layer: .working, details: "сохранено: \(entries)")]
    }

    private func extractCandidates(from userText: String, assistantText: String) -> [WorkingMemoryCandidate] {
        let normalized = userText.lowercased()
        var result: [WorkingMemoryCandidate] = []

        if let value = extractValue(in: userText, prefixes: ["goal:", "цель:"]) {
            result.append(.init(key: "task.goal", value: value, confidence: 0.9))
        } else if normalized.contains("need to") || normalized.contains("нужно") {
            result.append(.init(key: "task.goal", value: userText, confidence: 0.75))
        }

        if let value = extractValue(in: userText, prefixes: ["constraint:", "ограничение:"]) {
            result.append(.init(key: "task.constraints", value: value, confidence: 0.85))
        }

        if let value = extractValue(in: userText, prefixes: ["step:", "шаг:"]) {
            result.append(.init(key: "task.current_step", value: value, confidence: 0.8))
        }

        if userText.contains("?") {
            result.append(.init(key: "task.open_question", value: userText, confidence: 0.75))
        }

        if let value = extractValue(in: assistantText, prefixes: ["decision:", "решение:"]) {
            result.append(.init(key: "task.decision", value: value, confidence: 0.8))
        }

        return result
    }

    private func merge(
        active: [WorkingMemoryItem],
        with candidates: [WorkingMemoryCandidate]
    ) -> (items: [WorkingMemoryItem], changedEntries: [String]) {
        var map = Dictionary(uniqueKeysWithValues: active.map { ($0.key, $0) })
        let now = Date()
        let taskID = "global"
        var changedEntries: [String] = []

        for candidate in candidates {
            let trimmedValue = candidate.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedValue.isEmpty else { continue }

            let current = map[candidate.key]
            if current?.value != trimmedValue || current?.status != .active {
                changedEntries.append("\(candidate.key)=\(normalizeMemoryText(trimmedValue))")
            }
            map[candidate.key] = WorkingMemoryItem(
                id: current?.id ?? UUID(),
                taskID: taskID,
                key: candidate.key,
                value: trimmedValue,
                status: .active,
                confidence: candidate.confidence,
                updatedAt: now
            )
        }

        return (map.values.sorted { $0.key < $1.key }, Array(Set(changedEntries)))
    }

    private func resolveKeys(from userText: String, assistantText: String) -> [String] {
        let markerSet = ["done", "completed", "resolved", "выполнено", "закрыто", "решено"]
        let combined = "\(userText.lowercased()) \(assistantText.lowercased())"
        let hasCompletionMarker = markerSet.contains { combined.contains($0) }
        guard hasCompletionMarker else { return [] }
        return ["task.current_step", "task.open_question"]
    }

    private func extractValue(in text: String, prefixes: [String]) -> String? {
        let lines = text.split(separator: "\n").map(String.init)
        for line in lines {
            let lowercasedLine = line.lowercased()
            for prefix in prefixes where lowercasedLine.hasPrefix(prefix) {
                let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }
}

final class UpdateLongTermMemoryUseCase: UpdateLongTermMemoryUseCaseProtocol {
    private let longTermRepository: LongTermMemoryRepositoryProtocol
    private let messageRepository: MessageRepositoryProtocol
    private let llmClient: LLMClientProtocol
    private let legacyFactsRepository: FactsRepositoryProtocol?
    private let decoder = JSONDecoder()
    private let threshold = 0.7

    init(
        longTermRepository: LongTermMemoryRepositoryProtocol,
        messageRepository: MessageRepositoryProtocol,
        llmClient: LLMClientProtocol,
        legacyFactsRepository: FactsRepositoryProtocol?
    ) {
        self.longTermRepository = longTermRepository
        self.messageRepository = messageRepository
        self.llmClient = llmClient
        self.legacyFactsRepository = legacyFactsRepository
    }

    func execute(latestUserMessage: String, settings: LLMSettings) async throws -> [MemoryWriteEvent] {
        let trimmed = latestUserMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        try await migrateStickyFactsIfNeeded()
        let existing = try await longTermRepository.fetch(namespaces: nil)
        let extractionMessages = try await buildExtractionMessages(latestUserMessage: trimmed)
        let extracted = try await extractMemoryUsingLLM(messages: extractionMessages, settings: settings)
        let mergeResult = mergeMemory(existing: existing, with: extracted)
        let merged = mergeResult.items
        if !merged.isEmpty {
            try await longTermRepository.upsert(items: merged)
        }
        guard !mergeResult.changedEntries.isEmpty else { return [] }
        let entries = mergeResult.changedEntries.sorted().joined(separator: " | ")
        return [MemoryWriteEvent(layer: .longTerm, details: "сохранено: \(entries)")]
    }

    private func extractMemoryUsingLLM(messages: [ChatMessage], settings: LLMSettings) async throws -> [LongTermMemoryCandidate] {
        let response = try await llmClient.send(
            request: LLMRequest(
                systemPrompt: """
                You extract durable long-term memory.
                Return strict JSON object with optional keys:
                profile, decisions, knowledge.
                Each value must be a short string.
                Exclude volatile or turn-local details.
                """,
                shortTermMessages: messages,
                workingMemory: [],
                longTermMemory: [],
                settings: LLMSettings(
                    model: settings.model,
                    temperature: 0.0,
                    windowSize: 1,
                    isRAGEnabled: settings.isRAGEnabled,
                    ragChunkingStrategy: settings.ragChunkingStrategy,
                    isMemoryEnabled: settings.isMemoryEnabled,
                    plannerInvariants: settings.plannerInvariants
                )
            )
        )

        let payload = extractJSONObject(from: response.content)
        guard let data = payload.data(using: String.Encoding.utf8) else { return [] }
        let decoded = try decoder.decode(LLMLongTermExtractionResult.self, from: data)
        return decoded.candidates
    }

    private func buildExtractionMessages(latestUserMessage: String) async throws -> [ChatMessage] {
        let history = try await messageRepository.fetchMessages()
        let assistantReply = history
            .last(where: { $0.role == .assistant })?
            .content
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let assistantContent: String
        if let assistantReply, !assistantReply.isEmpty {
            assistantContent = assistantReply
        } else {
            assistantContent = "No previous assistant response."
        }

        return [
            ChatMessage(role: .assistant, content: assistantContent),
            ChatMessage(role: .user, content: latestUserMessage)
        ]
    }

    private func extractJSONObject(from text: String) -> String {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return "{}"
        }
        return String(text[start...end])
    }

    private func mergeMemory(
        existing: [LongTermMemoryItem],
        with extracted: [LongTermMemoryCandidate]
    ) -> (items: [LongTermMemoryItem], changedEntries: [String]) {
        var map = Dictionary(uniqueKeysWithValues: existing.map { ("\($0.namespace.rawValue)|\($0.key)", $0) })
        let now = Date()
        var changedEntries: [String] = []

        for candidate in extracted where candidate.confidence >= threshold {
            let value = candidate.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            let mapKey = "\(candidate.namespace.rawValue)|\(candidate.key)"

            let current = map[mapKey]
            if current?.value != value {
                changedEntries.append("\(candidate.namespace.rawValue).\(candidate.key)=\(normalizeMemoryText(value))")
            }
            map[mapKey] = LongTermMemoryItem(
                id: current?.id ?? UUID(),
                namespace: candidate.namespace,
                key: candidate.key,
                value: value,
                confidence: candidate.confidence,
                source: candidate.source,
                updatedAt: now
            )
        }

        let sorted = map.values.sorted {
            if $0.namespace != $1.namespace {
                return $0.namespace.rawValue < $1.namespace.rawValue
            }
            return $0.key < $1.key
        }
        return (sorted, Array(Set(changedEntries)))
    }

    private func migrateStickyFactsIfNeeded() async throws {
        guard let legacyFactsRepository else { return }
        let existing = try await longTermRepository.fetch(namespaces: nil)
        guard existing.isEmpty else { return }

        let stickyFacts = try await legacyFactsRepository.fetchFacts()
        guard !stickyFacts.isEmpty else { return }

        let converted = stickyFacts.map(LongTermMemoryItem.init(stickyFact:))
        try await longTermRepository.upsert(items: converted)
    }
}

private struct WorkingMemoryCandidate {
    let key: String
    let value: String
    let confidence: Double
}

private struct LongTermMemoryCandidate {
    let namespace: LongTermMemoryNamespace
    let key: String
    let value: String
    let confidence: Double
    let source: String
}

private struct LLMLongTermExtractionResult: Decodable {
    let profile: String?
    let decisions: String?
    let knowledge: String?

    var candidates: [LongTermMemoryCandidate] {
        var result: [LongTermMemoryCandidate] = []
        if let profile, !profile.isEmpty {
            result.append(.init(namespace: .profile, key: "summary", value: profile, confidence: 0.8, source: "llm-extraction"))
        }
        if let decisions, !decisions.isEmpty {
            result.append(.init(namespace: .decisions, key: "latest", value: decisions, confidence: 0.8, source: "llm-extraction"))
        }
        if let knowledge, !knowledge.isEmpty {
            result.append(.init(namespace: .knowledge, key: "summary", value: knowledge, confidence: 0.75, source: "llm-extraction"))
        }
        return result
    }
}

private func normalizeMemoryText(_ text: String, maxLength: Int = 120) -> String {
    let flattened = text
        .replacingOccurrences(of: "\n", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard flattened.count > maxLength else { return flattened }
    return String(flattened.prefix(maxLength)) + "..."
}

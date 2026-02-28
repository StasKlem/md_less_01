//
//  ChatSession.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

struct ConversationBranch: Identifiable, Equatable, Codable {
    let id: UUID
    let parentBranchId: UUID?
    let forkedFromMessageId: UUID?
    let createdAt: Date
}

protocol ChatSessionProtocol: Actor {
    var messages: [Message] { get }
    var isProcessing: Bool { get }
    var conversationSummary: String? { get }
    var sessionId: UUID { get }
    var createdDate: Date { get }
    var messageCount: Int { get }
    var activeBranchId: UUID { get }
    var availableBranches: [ConversationBranch] { get }

    func configure(storage: ChatStorageProtocol)
    func configureSummaryStorage(storage: ConversationSummaryStorageProtocol)
    func configureConversationRepository(repository: ConversationRepositoryProtocol)
    func loadFromStorage() async
    func loadSummaryFromStorage() async
    func saveToStorage() async
    func saveSummaryToStorage() async
    func clearStorage() async
    func clearSummaryStorage() async
    func loadConversationState() async
    func saveConversationState() async
    func clearConversationState() async
    func addMessage(_ message: Message)
    func updateMessage(id: UUID, content: String, isStreaming: Bool, error: String?)
    func appendToMessage(id: UUID, content: String)
    func completeStreaming(for messageId: UUID)
    func updateMessageTokens(id: UUID, promptTokens: Int, completionTokens: Int, totalTokens: Int)
    func updateMessageSummaryTokens(id: UUID, promptTokens: Int, completionTokens: Int)
    func setProcessing(_ processing: Bool)
    func updateSummary(_ summary: String)
    func clearMessages()
    func createBranch(fromMessageId messageId: UUID?) -> ConversationBranch
    func switchBranch(to branchId: UUID) -> Bool
    func messagesForAPI(systemPrompt: String, summarizationStrategy: SummarizationStrategy) -> [[String: String]]
    func needsSummarization(strategy: SummarizationStrategy) -> Bool
    func messagesToSummarize(strategy: SummarizationStrategy) -> [Message]
    func messagesToSummarize(keepCount: Int) -> [Message]
}

/// Represents a chat session containing messages and metadata
actor ChatSession: ChatSessionProtocol {

    private(set) var isProcessing: Bool = false
    private(set) var conversationSummary: String?
    private(set) var activeBranchId: UUID

    private let id: UUID
    private let createdAt: Date
    private weak var chatStorage: ChatStorageProtocol?
    private var summaryStorage: ConversationSummaryStorageProtocol?
    private weak var conversationRepository: ConversationRepositoryProtocol?
    private var branchMessages: [UUID: [Message]]
    private var branches: [ConversationBranch]

    init(id: UUID = UUID(), createdAt: Date = Date()) {
        let rootBranch = ConversationBranch(
            id: UUID(),
            parentBranchId: nil,
            forkedFromMessageId: nil,
            createdAt: createdAt
        )

        self.activeBranchId = rootBranch.id
        self.branchMessages = [rootBranch.id: []]
        self.branches = [rootBranch]
        self.id = id
        self.createdAt = createdAt
    }

    var messages: [Message] {
        branchMessages[activeBranchId] ?? []
    }

    var availableBranches: [ConversationBranch] {
        branches
    }

    func configure(storage: ChatStorageProtocol) {
        self.chatStorage = storage
    }

    func configureSummaryStorage(storage: ConversationSummaryStorageProtocol) {
        self.summaryStorage = storage
    }

    func configureConversationRepository(repository: ConversationRepositoryProtocol) {
        self.conversationRepository = repository
    }

    func loadFromStorage() async {
        guard let storage = chatStorage else { return }
        branchMessages[activeBranchId] = await storage.loadMessages()
    }

    func loadSummaryFromStorage() async {
        conversationSummary = await summaryStorage?.loadSummary()
    }

    func saveToStorage() async {
        guard let storage = chatStorage else { return }
        await storage.saveMessages(messages)
    }

    func saveSummaryToStorage() async {
        guard let summary = conversationSummary else { return }
        try? await summaryStorage?.saveSummary(summary)
    }

    func clearStorage() async {
        await chatStorage?.clearMessages()
    }

    func clearSummaryStorage() async {
        try? await summaryStorage?.clearSummary()
    }

    func loadConversationState() async {
        if let state = await conversationRepository?.loadConversationState() {
            let validStates = state.branches
            guard !validStates.isEmpty else { return }

            let messagesByBranch = Dictionary(uniqueKeysWithValues: validStates.map { ($0.branch.id, $0.messages) })
            let branchDefinitions = validStates.map(\.branch)

            guard messagesByBranch[state.activeBranchId] != nil else { return }

            branchMessages = messagesByBranch
            branches = branchDefinitions
            activeBranchId = state.activeBranchId
            conversationSummary = state.conversationSummary
            return
        }

        await loadFromStorage()
        await loadSummaryFromStorage()
    }

    func saveConversationState() async {
        guard let conversationRepository else {
            await saveToStorage()
            await saveSummaryToStorage()
            return
        }

        let state = ConversationState(
            activeBranchId: activeBranchId,
            branches: branches.map { branch in
                ConversationBranchState(branch: branch, messages: branchMessages[branch.id] ?? [])
            },
            conversationSummary: conversationSummary
        )

        await conversationRepository.saveConversationState(state)
    }

    func clearConversationState() async {
        await conversationRepository?.clearConversationState()
    }

    var sessionId: UUID { id }
    var createdDate: Date { createdAt }
    var messageCount: Int { messages.count }

    func addMessage(_ message: Message) {
        updateCurrentBranch { $0.append(message) }
    }

    func updateMessage(id: UUID, content: String, isStreaming: Bool = false, error: String? = nil) {
        updateCurrentBranch { messages in
            guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
            messages[index].content = content
            messages[index].isStreaming = isStreaming
            messages[index].error = error
        }
    }

    func appendToMessage(id: UUID, content: String) {
        updateCurrentBranch { messages in
            guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
            messages[index].content += content
        }
    }

    func completeStreaming(for messageId: UUID) {
        updateCurrentBranch { messages in
            guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
            messages[index].isStreaming = false
        }
    }

    func updateMessageTokens(id: UUID, promptTokens: Int, completionTokens: Int, totalTokens: Int) {
        updateCurrentBranch { messages in
            guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
            messages[index].promptTokens = promptTokens
            messages[index].completionTokens = completionTokens
            messages[index].totalTokens = totalTokens
        }
    }

    func updateMessageSummaryTokens(id: UUID, promptTokens: Int, completionTokens: Int) {
        updateCurrentBranch { messages in
            guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
            messages[index].promptTokensForSummary = promptTokens
            messages[index].completionTokensForSummary = completionTokens
        }
    }

    func setProcessing(_ processing: Bool) {
        isProcessing = processing
    }

    func updateSummary(_ summary: String) {
        conversationSummary = summary
        Task { await saveSummaryToStorage() }
    }

    func clearMessages() {
        branchMessages = [activeBranchId: []]
        branches = [ConversationBranch(id: activeBranchId, parentBranchId: nil, forkedFromMessageId: nil, createdAt: Date())]
        conversationSummary = nil
        Task { await clearSummaryStorage() }
    }

    func createBranch(fromMessageId messageId: UUID? = nil) -> ConversationBranch {
        let baseMessages = messages
        let forkMessages: [Message]

        if let messageId, let index = baseMessages.firstIndex(where: { $0.id == messageId }) {
            forkMessages = Array(baseMessages.prefix(through: index))
        } else {
            forkMessages = baseMessages
        }

        let branch = ConversationBranch(
            id: UUID(),
            parentBranchId: activeBranchId,
            forkedFromMessageId: messageId,
            createdAt: Date()
        )

        branchMessages[branch.id] = forkMessages
        branches.append(branch)

        return branch
    }

    func switchBranch(to branchId: UUID) -> Bool {
        guard branchMessages[branchId] != nil else { return false }
        activeBranchId = branchId
        return true
    }

    func messagesForAPI(systemPrompt: String = "", summarizationStrategy: SummarizationStrategy = .none) -> [[String: String]] {
        var result: [[String: String]] = []

        if !systemPrompt.isEmpty {
            result.append(["role": "system", "content": systemPrompt])
        }

        if let summary = conversationSummary, !summary.isEmpty {
            switch summarizationStrategy {
            case .none:
                break
            case .keepLastMessages(let keepCount):
                let userAndAssistantMessages = messages.filter { $0.role == .user || $0.role == .assistant }
                if userAndAssistantMessages.count > keepCount {
                    result.append([
                        "role": "system",
                        "content": "Предыдущий контекст разговора (резюме): \(summary)"
                    ])

                    let messagesToKeep = Array(userAndAssistantMessages.suffix(keepCount))
                    for message in messagesToKeep {
                        if message.error == nil, !message.content.isEmpty {
                            result.append([
                                "role": message.role.rawValue,
                                "content": message.content
                            ])
                        }
                    }

                    return result
                }
            case .windowLastMessages(let keepCount):
                let userAndAssistantMessages = messages.filter { $0.role == .user || $0.role == .assistant }
                let messagesToKeep = Array(userAndAssistantMessages.suffix(keepCount))
                for message in messagesToKeep {
                    if message.error == nil, !message.content.isEmpty {
                        result.append([
                            "role": message.role.rawValue,
                            "content": message.content
                        ])
                    }
                }
                return result
            }
        }

        for message in messages {
            guard message.error == nil else { continue }
            guard !message.content.isEmpty else { continue }
            result.append([
                "role": message.role.rawValue,
                "content": message.content
            ])
        }

        return result
    }

    func needsSummarization(strategy: SummarizationStrategy) -> Bool {
        switch strategy {
        case .none:
            return false
        case .keepLastMessages(let keepCount):
            let userAndAssistantMessages = messages.filter { $0.role == .user || $0.role == .assistant }
            return userAndAssistantMessages.count > keepCount
        case .windowLastMessages:
            return false
        }
    }

    func messagesToSummarize(strategy: SummarizationStrategy) -> [Message] {
        switch strategy {
        case .none:
            return []
        case .keepLastMessages(let keepCount):
            return messagesToSummarize(keepCount: keepCount)
        case .windowLastMessages:
            return []
        }
    }

    func messagesToSummarize(keepCount: Int) -> [Message] {
        let userAndAssistantMessages = messages.filter { $0.role == .user || $0.role == .assistant }
        if userAndAssistantMessages.count > keepCount {
            let countToSummarize = userAndAssistantMessages.count - keepCount
            return Array(userAndAssistantMessages.prefix(countToSummarize))
        }
        return []
    }

    private func updateCurrentBranch(_ updater: (inout [Message]) -> Void) {
        var currentMessages = branchMessages[activeBranchId] ?? []
        updater(&currentMessages)
        branchMessages[activeBranchId] = currentMessages
    }
}

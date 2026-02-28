//
//  ChatSession.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

/// Represents a chat session containing messages and metadata
actor ChatSession {

    private(set) var messages: [Message] = []
    private(set) var isProcessing: Bool = false
    private(set) var conversationSummary: String?

    private let id: UUID
    private let createdAt: Date
    private weak var chatStorage: ChatStorageProtocol?
    private var summaryStorage: ConversationSummaryStorageProtocol?

    init(id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.createdAt = createdAt
    }

    func configure(storage: ChatStorageProtocol) {
        self.chatStorage = storage
    }

    func configureSummaryStorage(storage: ConversationSummaryStorageProtocol) {
        self.summaryStorage = storage
    }

    func loadFromStorage() {
        guard let storage = chatStorage else { return }
        messages = storage.loadMessages()
    }

    func loadSummaryFromStorage() {
        conversationSummary = summaryStorage?.loadSummary()
    }

    func saveToStorage() {
        guard let storage = chatStorage else { return }
        storage.saveMessages(messages)
    }

    func saveSummaryToStorage() {
        guard let summary = conversationSummary else { return }
        try? summaryStorage?.saveSummary(summary)
    }

    func clearStorage() {
        chatStorage?.clearMessages()
    }

    func clearSummaryStorage() {
        try? summaryStorage?.clearSummary()
    }

    var sessionId: UUID { id }
    var createdDate: Date { createdAt }
    var messageCount: Int { messages.count }

    func addMessage(_ message: Message) {
        messages.append(message)
    }

    func updateMessage(id: UUID, content: String, isStreaming: Bool = false, error: String? = nil) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content = content
        messages[index].isStreaming = isStreaming
        messages[index].error = error
    }

    func appendToMessage(id: UUID, content: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content += content
    }

    func completeStreaming(for messageId: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        messages[index].isStreaming = false
    }

    func updateMessageTokens(id: UUID, promptTokens: Int, completionTokens: Int, totalTokens: Int) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].promptTokens = promptTokens
        messages[index].completionTokens = completionTokens
        messages[index].totalTokens = totalTokens
    }

    func updateMessageSummaryTokens(id: UUID, promptTokens: Int, completionTokens: Int) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].promptTokensForSummary = promptTokens
        messages[index].completionTokensForSummary = completionTokens
    }

    func setProcessing(_ processing: Bool) {
        isProcessing = processing
    }

    func updateSummary(_ summary: String) {
        conversationSummary = summary
        saveSummaryToStorage()
    }

    func clearMessages() {
        messages.removeAll()
        conversationSummary = nil
        clearSummaryStorage()
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
        }
    }

    func messagesToSummarize(strategy: SummarizationStrategy) -> [Message] {
        switch strategy {
        case .none:
            return []
        case .keepLastMessages(let keepCount):
            return messagesToSummarize(keepCount: keepCount)
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
}

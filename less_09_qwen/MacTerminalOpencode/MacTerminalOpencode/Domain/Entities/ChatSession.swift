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
    
    private let id: UUID
    private let createdAt: Date
    private weak var chatStorage: ChatStorageProtocol?
    
    init(id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.createdAt = createdAt
    }
    
    func configure(storage: ChatStorageProtocol) {
        self.chatStorage = storage
    }
    
    func loadFromStorage() {
        guard let storage = chatStorage else { return }
        messages = storage.loadMessages()
    }
    
    func saveToStorage() {
        guard let storage = chatStorage else { return }
        storage.saveMessages(messages)
    }
    
    func clearStorage() {
        chatStorage?.clearMessages()
    }
    
    var sessionId: UUID { id }
    var createdDate: Date { createdAt }
    var messageCount: Int { messages.count }
    
    /// Adds a new message to the session
    func addMessage(_ message: Message) {
        messages.append(message)
    }
    
    /// Updates an existing message by ID
    func updateMessage(id: UUID, content: String, isStreaming: Bool = false, error: String? = nil) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content = content
        messages[index].isStreaming = isStreaming
        messages[index].error = error
    }
    
    /// Appends content to an existing message (for streaming)
    func appendToMessage(id: UUID, content: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content += content
    }
    
    /// Marks the message as complete
    func completeStreaming(for messageId: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        messages[index].isStreaming = false
    }
    
    /// Updates token counts for a message
    func updateMessageTokens(id: UUID, promptTokens: Int, completionTokens: Int, totalTokens: Int) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].promptTokens = promptTokens
        messages[index].completionTokens = completionTokens
        messages[index].totalTokens = totalTokens
    }

    /// Sets processing state
    func setProcessing(_ processing: Bool) {
        isProcessing = processing
    }
    
    /// Clears all messages from the session
    func clearMessages() {
        messages.removeAll()
    }
    
    /// Returns messages formatted for API request
    func messagesForAPI() -> [[String: String]] {
        messages.compactMap { message in
            guard message.error == nil else { return nil }
            return [
                "role": message.role.rawValue,
                "content": message.content
            ]
        }
    }

    /// Returns messages formatted for API request with summarization applied
    func messagesForAPI(with strategy: SummarizationStrategy, summaryPrompt: String, summarizeUseCase: SummarizeMessagesUseCaseProtocol) async -> [[String: String]] {
        let result = await summarizeUseCase.execute(
            messages: messages,
            strategy: strategy,
            summaryPrompt: summaryPrompt
        )
        return result.messagesForAPI
    }

    /// Clears the summary cache when chat is cleared
    func clearSummary(summaryStorage: SummaryStorageProtocol) {
        summaryStorage.clearSummary()
    }
}

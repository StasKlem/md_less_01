//
//  Message.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

/// Represents the role of a message sender in the chat
enum MessageRole: String, Codable, CaseIterable {
    case user
    case assistant
    case system
}

/// Represents a single message in the chat conversation
struct Message: Identifiable, Equatable, Codable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date
    var isStreaming: Bool
    var error: String?
    
    // Token counts
    var promptTokens: Int?
    var completionTokens: Int?
    var totalTokens: Int?

    // Token counts for summary generation
    var promptTokensForSummary: Int?
    var completionTokensForSummary: Int?

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false,
        error: String? = nil,
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        totalTokens: Int? = nil,
        promptTokensForSummary: Int? = nil,
        completionTokensForSummary: Int? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.error = error
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.promptTokensForSummary = promptTokensForSummary
        self.completionTokensForSummary = completionTokensForSummary
    }

    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id
    }
}

extension Message {
    /// Creates a user message with the given content
    static func user(_ content: String) -> Message {
        Message(role: .user, content: content)
    }

    /// Creates an assistant message placeholder for streaming
    static func assistantStreaming() -> Message {
        Message(role: .assistant, content: "", isStreaming: true)
    }

    /// Creates a system message with the given content
    static func system(_ content: String) -> Message {
        Message(role: .system, content: content)
    }
    
    /// Creates an assistant message with token counts
    static func assistant(_ content: String, promptTokens: Int?, completionTokens: Int?, totalTokens: Int?) -> Message {
        Message(
            role: .assistant,
            content: content,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: totalTokens
        )
    }

    /// Creates an assistant message with all token counts including summary
    static func assistant(_ content: String, promptTokens: Int?, completionTokens: Int?, totalTokens: Int?, promptTokensForSummary: Int?, completionTokensForSummary: Int?) -> Message {
        Message(
            role: .assistant,
            content: content,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: totalTokens,
            promptTokensForSummary: promptTokensForSummary,
            completionTokensForSummary: completionTokensForSummary
        )
    }
}

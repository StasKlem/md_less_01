//
//  ConversationSummaryStorageProtocol.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 26.02.2026.
//

import Foundation

protocol ConversationSummaryStorageProtocol {
    func saveSummary(_ summary: String) throws
    func loadSummary() -> String?
    func clearSummary() throws
}

struct ConversationBranchState: Codable, Equatable {
    let branch: ConversationBranch
    let messages: [Message]
}

struct ConversationState: Codable, Equatable {
    let activeBranchId: UUID
    let branches: [ConversationBranchState]
    let conversationSummary: String?
}

protocol ConversationRepositoryProtocol: AnyObject {
    func saveConversationState(_ state: ConversationState)
    func loadConversationState() -> ConversationState?
    func clearConversationState()
}

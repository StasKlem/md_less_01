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

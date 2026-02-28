//
//  ConversationSummaryStorage.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 26.02.2026.
//

import Foundation

final class ConversationSummaryStorage: ConversationSummaryStorageProtocol {

    private let userDefaults: UserDefaults
    private let storageKey = "conversationSummary"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func saveSummary(_ summary: String) throws {
        userDefaults.set(summary, forKey: storageKey)
    }

    func loadSummary() -> String? {
        return userDefaults.string(forKey: storageKey)
    }

    func clearSummary() throws {
        userDefaults.removeObject(forKey: storageKey)
    }
}

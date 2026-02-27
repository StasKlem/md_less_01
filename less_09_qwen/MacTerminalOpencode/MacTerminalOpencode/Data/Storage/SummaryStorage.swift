//
//  SummaryStorage.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 26.02.2026.
//

import Foundation

/// UserDefaults-based implementation of SummaryStorageProtocol
final class SummaryStorage: SummaryStorageProtocol {
    
    private let defaults: UserDefaults
    
    private enum Keys {
        static let chatSummary = "llm.chat.summary"
    }
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    func saveSummary(_ summary: String) {
        defaults.set(summary, forKey: Keys.chatSummary)
        defaults.synchronize()
    }
    
    func loadSummary() -> String? {
        defaults.string(forKey: Keys.chatSummary)
    }
    
    func clearSummary() {
        defaults.removeObject(forKey: Keys.chatSummary)
        defaults.synchronize()
    }
}

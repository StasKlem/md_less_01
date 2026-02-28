//
//  ChatStorage.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

protocol ChatStorageProtocol: AnyObject {
    func saveMessages(_ messages: [Message])
    func loadMessages() -> [Message]
    func clearMessages()
}

final class ChatStorage: ChatStorageProtocol {
    
    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    private enum Keys {
        static let chatMessages = "llm.chat.messages"
    }
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }
    
    func saveMessages(_ messages: [Message]) {
        do {
            let data = try encoder.encode(messages)
            defaults.set(data, forKey: Keys.chatMessages)
            defaults.synchronize()
        } catch {
            print("[ChatStorage] Failed to save messages: \(error)")
        }
    }
    
    func loadMessages() -> [Message] {
        guard let data = defaults.data(forKey: Keys.chatMessages) else {
            return []
        }
        
        do {
            return try decoder.decode([Message].self, from: data)
        } catch {
            print("[ChatStorage] Failed to load messages: \(error)")
            return []
        }
    }
    
    func clearMessages() {
        defaults.removeObject(forKey: Keys.chatMessages)
        defaults.synchronize()
    }
}

final class ConversationRepository: ConversationRepositoryProtocol {

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private enum Keys {
        static let conversationState = "llm.chat.conversation.state"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func saveConversationState(_ state: ConversationState) {
        do {
            let data = try encoder.encode(state)
            defaults.set(data, forKey: Keys.conversationState)
            defaults.synchronize()
        } catch {
            print("[ConversationRepository] Failed to save state: \(error)")
        }
    }

    func loadConversationState() -> ConversationState? {
        guard let data = defaults.data(forKey: Keys.conversationState) else { return nil }

        do {
            return try decoder.decode(ConversationState.self, from: data)
        } catch {
            print("[ConversationRepository] Failed to load state: \(error)")
            return nil
        }
    }

    func clearConversationState() {
        defaults.removeObject(forKey: Keys.conversationState)
        defaults.synchronize()
    }
}

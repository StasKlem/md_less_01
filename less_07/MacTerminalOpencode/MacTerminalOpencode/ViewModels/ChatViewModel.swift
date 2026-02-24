//
//  ChatViewModel.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

/// Represents the display state for a message in the UI
struct MessageDisplayItem: Identifiable, Equatable {
    let id: UUID
    let role: MessageRole
    let content: NSAttributedString
    let timestamp: Date
    let isStreaming: Bool
    let error: String?
    let rawContent: String
    
    init(from message: Message) {
        self.id = message.id
        self.role = message.role
        self.rawContent = message.content
        self.content = MarkdownAttributedString.parse(message.content)
        self.timestamp = message.timestamp
        self.isStreaming = message.isStreaming
        self.error = message.error
    }
}

/// Callback types for ChatViewModel state changes
enum ChatViewModelEvent {
    case messagesUpdated([MessageDisplayItem])
    case processingStateChanged(Bool)
    case errorOccurred(String)
    case messageSent
}

/// Manages chat state and coordinates message sending
@MainActor
final class ChatViewModel {
    
    private(set) var messages: [MessageDisplayItem] = []
    private(set) var isProcessing: Bool = false
    
    private let sendMessageUseCase: SendMessageUseCaseProtocol
    private let chatSession: ChatSession
    private let settingsViewModel: SettingsViewModel
    private let metricsViewModel: MetricsViewModel
    private let chatStorage: ChatStorage
    
    var onEvent: ((ChatViewModelEvent) -> Void)?
    
    init(
        sendMessageUseCase: SendMessageUseCaseProtocol,
        chatSession: ChatSession,
        settingsViewModel: SettingsViewModel,
        metricsViewModel: MetricsViewModel,
        chatStorage: ChatStorage
    ) {
        self.sendMessageUseCase = sendMessageUseCase
        self.chatSession = chatSession
        self.settingsViewModel = settingsViewModel
        self.metricsViewModel = metricsViewModel
        self.chatStorage = chatStorage
        
        Task {
            await configureAndLoad()
        }
    }
    
    private func configureAndLoad() async {
        await chatSession.configure(storage: chatStorage)
        
        if settingsViewModel.currentSettings.saveContext {
            await chatSession.loadFromStorage()
            await reloadMessages()
        }
    }
    
    /// Sends a new message
    func sendMessage(_ content: String) {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedContent.isEmpty, !isProcessing else { return }
        
        print("[ChatViewModel] Sending message: \(trimmedContent.prefix(50))...")
        
        metricsViewModel.startRequest()
        
        isProcessing = true
        onEvent?(.processingStateChanged(true))
        
        Task { [weak self] in
            guard let self else { return }
            
            await self.sendMessageUseCase.execute(
                content: trimmedContent,
                settings: self.settingsViewModel.currentSettings
            ) { [weak self] (event: SendMessageEvent) in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    print("[ChatViewModel] Received event: \(event)")
                    self.handleSendEvent(event)
                }
            }
            
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isProcessing = false
                self.onEvent?(.processingStateChanged(false))
            }
        }
    }
    
    /// Clears all messages
    func clearChat() {
        Task { [weak self] in
            guard let self else { return }
            await self.chatSession.clearMessages()
            if self.settingsViewModel.currentSettings.saveContext {
                await self.chatSession.clearStorage()
            }
            self.messages = []
            self.onEvent?(.messagesUpdated([]))
        }
    }
    
    /// Reloads messages from the session
    func reloadMessages() async {
        let sessionMessages = await chatSession.messages
        messages = sessionMessages.map { MessageDisplayItem(from: $0) }
        onEvent?(.messagesUpdated(messages))
    }
    
    private func handleSendEvent(_ event: SendMessageEvent) {
        print("[ChatViewModel] Handling event: \(event)")
        
        switch event {
        case .messageAdded(let message):
            print("[ChatViewModel] Message added: \(message.role) - \(message.content.prefix(30))")
            Task { @MainActor [weak self] in
                await self?.reloadMessages()
            }
        case .chunkReceived(let messageId, let content):
            let wordCount = content.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
            metricsViewModel.recordTokens(max(1, wordCount))
            Task { @MainActor [weak self] in
                await self?.reloadMessages()
            }
        case .completed:
            metricsViewModel.completeRequest()
            onEvent?(.messageSent)
            if settingsViewModel.currentSettings.saveContext {
                Task {
                    await chatSession.saveToStorage()
                }
            }
        case .error(_, let error):
            onEvent?(.errorOccurred(error.errorDescription ?? "Unknown error"))
        }
    }
}

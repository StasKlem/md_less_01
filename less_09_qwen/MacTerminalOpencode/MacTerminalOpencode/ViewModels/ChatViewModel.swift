//
//  ChatViewModel.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation
import AppKit

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
        self.timestamp = message.timestamp
        self.isStreaming = message.isStreaming
        self.error = message.error
        
        // Parse Markdown only for non-streaming messages
        if message.isStreaming {
            self.content = NSAttributedString(
                string: message.content,
                attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]
            )
        } else {
            self.content = MarkdownAttributedString.parse(message.content)
        }
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
    
    // Throttle UI updates during streaming
    private var streamingUpdateTimer: Timer?
    private var pendingStreamingUpdate: Bool = false

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
    
    /// Updates only the last streaming message with throttling
    private func updateLastMessage() async {
        guard let lastMessage = await chatSession.messages.last else { return }
        
        // Find existing message or create new one
        if let index = messages.firstIndex(where: { $0.id == lastMessage.id }) {
            // Update existing
            messages[index] = MessageDisplayItem(from: lastMessage)
        } else {
            // Add new
            messages.append(MessageDisplayItem(from: lastMessage))
        }
        
        // Throttle updates to 15 FPS during streaming
        if streamingUpdateTimer == nil || !streamingUpdateTimer!.isValid {
            streamingUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.streamingUpdateTimer = nil
                    self?.onEvent?(.messagesUpdated(self?.messages ?? []))
                }
            }
        } else {
            pendingStreamingUpdate = true
        }
    }
    
    /// Adds a new message to the display list
    private func addMessage(_ message: Message) {
        let displayItem = MessageDisplayItem(from: message)
        messages.append(displayItem)
        onEvent?(.messagesUpdated(messages))
    }
    
    private func handleSendEvent(_ event: SendMessageEvent) {
        print("[ChatViewModel] Handling event: \(event)")

        switch event {
        case .messageAdded(let message):
            print("[ChatViewModel] Message added: \(message.role) - \(message.content.prefix(30))")
            Task { @MainActor [weak self] in
                self?.addMessage(message)
            }
        case .chunkReceived(let messageId, let content):
            let wordCount = content.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
            metricsViewModel.recordTokens(max(1, wordCount))
            Task { @MainActor [weak self] in
                await self?.updateLastMessage()
            }
        case .completed(let messageId, let promptTokens, let completionTokens, let totalTokens):
            metricsViewModel.completeRequest(promptTokens: promptTokens, completionTokens: completionTokens)
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

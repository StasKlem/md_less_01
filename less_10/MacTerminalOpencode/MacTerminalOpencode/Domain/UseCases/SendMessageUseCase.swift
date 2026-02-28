//
//  SendMessageUseCase.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

/// Callback types for message sending events
enum SendMessageEvent {
    case messageAdded(Message)
    case chunkReceived(messageId: UUID, content: String)
    case completed(messageId: UUID, promptTokens: Int, completionTokens: Int, totalTokens: Int)
    case error(messageId: UUID, error: AppError)
}

/// Protocol for message sending use case
protocol SendMessageUseCaseProtocol {
    func execute(
        content: String,
        settings: LLMSettings,
        behaviorStrategy: ChatBehaviorStrategy,
        onEvent: @escaping (SendMessageEvent) -> Void
    ) async
}

/// Orchestrates the process of sending a message to the LLM and receiving a response
final class SendMessageUseCase: SendMessageUseCaseProtocol {

    private let apiClient: LLMAPIClientProtocol
    private let keychainService: KeychainServiceProtocol
    private let chatSession: any ChatSessionProtocol

    init(
        apiClient: LLMAPIClientProtocol,
        keychainService: KeychainServiceProtocol,
        chatSession: any ChatSessionProtocol
    ) {
        self.apiClient = apiClient
        self.keychainService = keychainService
        self.chatSession = chatSession
    }

    /// Executes the message sending flow
    func execute(
        content: String,
        settings: LLMSettings,
        behaviorStrategy: ChatBehaviorStrategy,
        onEvent: @escaping (SendMessageEvent) -> Void
    ) async {
        do {
            let apiKey = try keychainService.loadAPIKey()
            print("[SendMessageUseCase] API Key loaded: \(apiKey != nil ? "yes" : "no")")
            print("[SendMessageUseCase] Settings - URL: \(settings.serverURL), Model: \(settings.modelName), Streaming: \(settings.enableStreaming)")

            let userMessage = Message.user(content)
            await chatSession.addMessage(userMessage)
            onEvent(.messageAdded(userMessage))

            await chatSession.setProcessing(true)

            let assistantMessage = Message.assistantStreaming()
            await chatSession.addMessage(assistantMessage)
            onEvent(.messageAdded(assistantMessage))

            let messages = await behaviorStrategy.prepareMessages(
                session: chatSession,
                systemPrompt: settings.systemPrompt
            )

            print("[SendMessageUseCase] Sending \(messages.count) messages to API")

            if settings.enableStreaming {
                print("[SendMessageUseCase] Using streaming mode")
                try await sendStreamingMessage(
                    messages: messages,
                    settings: settings,
                    apiKey: apiKey,
                    messageId: assistantMessage.id,
                    onEvent: onEvent
                )
            } else {
                print("[SendMessageUseCase] Using non-streaming mode")
                try await sendNonStreamingMessage(
                    messages: messages,
                    settings: settings,
                    apiKey: apiKey,
                    messageId: assistantMessage.id,
                    onEvent: onEvent
                )
            }

        } catch let error as AppError {
            print("[SendMessageUseCase] AppError: \(error.errorDescription ?? "unknown")")
            if let lastMessage = await chatSession.messages.last {
                await chatSession.updateMessage(id: lastMessage.id, content: "", isStreaming: false, error: error.errorDescription)
                onEvent(.error(messageId: lastMessage.id, error: error))
            }
        } catch {
            print("[SendMessageUseCase] Unknown error: \(error.localizedDescription)")
            let appError = AppError.unknown(error.localizedDescription)
            if let lastMessage = await chatSession.messages.last {
                await chatSession.updateMessage(id: lastMessage.id, content: "", isStreaming: false, error: appError.errorDescription)
                onEvent(.error(messageId: lastMessage.id, error: appError))
            }
        }

        await chatSession.setProcessing(false)
    }
    
    private func sendStreamingMessage(
        messages: [[String: String]],
        settings: LLMSettings,
        apiKey: String?,
        messageId: UUID,
        onEvent: @escaping (SendMessageEvent) -> Void
    ) async throws {
        let (promptTokens, completionTokens, totalTokens) = try await apiClient.streamMessage(
            messages: messages,
            settings: settings,
            apiKey: apiKey
        ) { [weak self] chunk in
            guard let self else { return }
            Task {
                await self.chatSession.appendToMessage(id: messageId, content: chunk)
                onEvent(.chunkReceived(messageId: messageId, content: chunk))
            }
        }

        await chatSession.completeStreaming(for: messageId)
        await chatSession.updateMessageTokens(id: messageId, promptTokens: promptTokens, completionTokens: completionTokens, totalTokens: totalTokens)
        onEvent(.completed(messageId: messageId, promptTokens: promptTokens, completionTokens: completionTokens, totalTokens: totalTokens))
    }

    private func sendNonStreamingMessage(
        messages: [[String: String]],
        settings: LLMSettings,
        apiKey: String?,
        messageId: UUID,
        onEvent: @escaping (SendMessageEvent) -> Void
    ) async throws {
        let (response, promptTokens, completionTokens, totalTokens) = try await apiClient.sendMessage(
            messages: messages,
            settings: settings,
            apiKey: apiKey
        )

        await chatSession.updateMessage(id: messageId, content: response, isStreaming: false, error: nil)
        await chatSession.updateMessageTokens(id: messageId, promptTokens: promptTokens, completionTokens: completionTokens, totalTokens: totalTokens)
        onEvent(.chunkReceived(messageId: messageId, content: response))
        onEvent(.completed(messageId: messageId, promptTokens: promptTokens, completionTokens: completionTokens, totalTokens: totalTokens))
    }
}

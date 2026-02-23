//
//  ChatRepository.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation
import Combine

/// Протокол репозитория для работы с чатом.
protocol ChatRepositoryProtocol {
    /// Отправить запрос и получить потоковый ответ как Publisher
    func sendChatRequest(
        messages: [Message],
        settings: ChatSettings,
        apiKey: String
    ) -> AnyPublisher<String, AppError>
    
    /// Отправить запрос без стриминга
    func sendNonStreamingRequest(
        messages: [Message],
        settings: ChatSettings,
        apiKey: String
    ) -> AnyPublisher<ChatResponse, AppError>
}

/// Реализация репозитория для работы с чатом.
final class ChatRepository: ChatRepositoryProtocol {
    
    // MARK: - Properties
    
    private let networkManager: NetworkManagerProtocol
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    // MARK: - Initialization
    
    init(
        networkManager: NetworkManagerProtocol = NetworkManager(),
        encoder: JSONEncoder = .init(),
        decoder: JSONDecoder = .init()
    ) {
        self.networkManager = networkManager
        self.encoder = encoder
        self.decoder = decoder
    }
    
    // MARK: - ChatRepositoryProtocol

    func sendChatRequest(
        messages: [Message],
        settings: ChatSettings,
        apiKey: String
    ) -> AnyPublisher<String, AppError> {
        guard let url = buildURL(from: settings) else {
            return Fail(error: AppError.invalidURL(settings.serverURL)).eraseToAnyPublisher()
        }

        let request = buildRequest(
            messages: messages,
            settings: settings,
            apiKey: apiKey
        )

        guard let body = request.body else {
            return Fail(error: AppError.parsing("Failed to encode request")).eraseToAnyPublisher()
        }

        // Создаём publisher из async stream
        return Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(.parsing("Repository deallocated")))
                return
            }
            
            Task {
                do {
                    let stream = self.networkManager.stream(url: url, body: body, headers: request.headers)
                    for try await chunk in stream {
                        promise(.success(chunk))
                    }
                    promise(.success("")) // Завершаем с пустым значением
                } catch {
                    let appError = self.mapError(error)
                    promise(.failure(appError))
                }
            }
        }
        .filter { !$0.isEmpty } // Фильтруем пустые чанки
        .eraseToAnyPublisher()
    }
    
    func sendNonStreamingRequest(
        messages: [Message],
        settings: ChatSettings,
        apiKey: String
    ) -> AnyPublisher<ChatResponse, AppError> {
        guard let url = buildURL(from: settings) else {
            return Fail(error: AppError.invalidURL(settings.serverURL)).eraseToAnyPublisher()
        }
        
        let request = buildRequest(
            messages: messages,
            settings: settings,
            apiKey: apiKey
        )
        
        guard let body = request.body else {
            return Fail(error: AppError.parsing("Failed to encode request")).eraseToAnyPublisher()
        }
        
        return Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(.parsing("Repository deallocated")))
                return
            }

            Task {
                do {
                    let data = try await self.networkManager.post(
                        url: url,
                        body: body,
                        headers: request.headers
                    )
                    let response = try self.decoder.decode(ChatResponse.self, from: data)
                    promise(.success(response))
                } catch {
                    let appError = self.mapError(error)
                    promise(.failure(appError))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    // MARK: - Private
    
    private func buildURL(from settings: ChatSettings) -> URL? {
        APIEndpoint.chatCompletions.buildURL(from: settings)
    }
    
    private func buildRequest(
        messages: [Message],
        settings: ChatSettings,
        apiKey: String
    ) -> (body: Data?, headers: [String: String]?) {
        let chatRequest = ChatRequest.from(messages: messages, settings: settings)
        
        var headers: [String: String] = [:]
        if !apiKey.isEmpty {
            headers["Authorization"] = "Bearer \(apiKey)"
        }
        
        do {
            let body = try encoder.encode(chatRequest)
            return (body, headers)
        } catch {
            logError("Failed to encode request: \(error)")
            return (nil, headers)
        }
    }
    
    private func mapError(_ error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        } else if let networkError = error as? NetworkError {
            return .network(networkError)
        } else {
            return .unknown(error)
        }
    }
}

// MARK: - Request Builder Helper

extension ChatRepository {
    
    /// Построить запрос с системным промптом
    func buildMessagesWithSystemPrompt(
        messages: [Message],
        systemPrompt: String?
    ) -> [Message] {
        guard let systemPrompt = systemPrompt, !systemPrompt.isEmpty else {
            return messages
        }
        
        // Проверить, есть ли уже системное сообщение
        let hasSystemMessage = messages.contains { $0.role == .system }
        
        guard !hasSystemMessage else {
            return messages
        }
        
        // Добавить системное сообщение в начало
        return [Message.system(systemPrompt)] + messages
    }
}

//
//  FetchModelsUseCase.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

/// Protocol for fetching available models
protocol FetchModelsUseCaseProtocol {
    func execute(settings: LLMSettings) async throws -> [String]
}

/// Fetches available models from the LLM API
final class FetchModelsUseCase: FetchModelsUseCaseProtocol {
    
    private let apiClient: LLMAPIClientProtocol
    private let keychainService: KeychainServiceProtocol
    
    init(
        apiClient: LLMAPIClientProtocol,
        keychainService: KeychainServiceProtocol
    ) {
        self.apiClient = apiClient
        self.keychainService = keychainService
    }
    
    /// Fetches the list of available models
    func execute(settings: LLMSettings) async throws -> [String] {
        let apiKey = try keychainService.loadAPIKey()
        return try await apiClient.fetchAvailableModels(settings: settings, apiKey: apiKey)
    }
}

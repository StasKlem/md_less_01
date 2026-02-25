//
//  Constants.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 22.02.2026.
//

import Foundation

enum Constants {
    enum Network {
        static let defaultTimeout: TimeInterval = 60.0
        static let streamingTimeout: TimeInterval = 120.0
    }
    
    enum API {
        static let defaultServerURL = "http://localhost:11434/v1"
        static let defaultModel = "deepseek/deepseek-v3.2"
        static let defaultSystemPrompt = "You are a helpful assistant."
    }
    
    enum UI {
        static let minimumChatWidth: CGFloat = 400
        static let minimumSettingsWidth: CGFloat = 200
        static let minimumMetricsHeight: CGFloat = 100
    }
    
    enum Storage {
        static let keychainService = "com.stasklem.MacTerminalOpencode"
    }
    
    enum Models {
        static let predefined: [ModelOption] = [
            ModelOption(id: "deepseek/deepseek-v3.2", displayName: "DeepSeek V3.2"),
            ModelOption(id: "openai/gpt-5.2", displayName: "GPT-5.2"),
            ModelOption(id: "google/gemini-3.1-pro-preview", displayName: "Gemini 3.1 Pro"),
            ModelOption(id: "qwen/qwen2.5-coder-7b-instruct", displayName: "qwen2.5-coder-7b-instruct"),
            ModelOption(id: "deepseek/deepseek-r1", displayName: "deepseek-r1"),
            ModelOption(id: "anthropic/claude-sonnet-4.6", displayName: "claude-sonnet-4.6"),
            ModelOption(id: "minimax/minimax-m2.5", displayName: "minimax-m2.5"),
            ModelOption(id: "google/gemini-3.1-pro-preview", displayName: "gemini-3.1-pro-preview"),
            ModelOption(id: "openai/gpt-3.5-turbo-0613", displayName: "gpt-3.5-turbo-0613")
        ]
    }
}

struct ModelOption: Equatable {
    let id: String
    let displayName: String
}

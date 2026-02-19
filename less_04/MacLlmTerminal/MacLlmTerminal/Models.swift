import Foundation

// MARK: - Available Models

enum AvailableModel: String, CaseIterable {
    case claudeSonnet = "anthropic/claude-sonnet-4.6"
    case deepseekV3 = "deepseek/deepseek-v3.2"
    case qwen35Plus = "qwen/qwen3.5-plus-02-15"
    case minimaxM25 = "minimax/minimax-m2.5"
    case glm5 = "z-ai/glm-5"
    
    var displayName: String {
        switch self {
        case .claudeSonnet: return "Claude Sonnet 4.6"
        case .deepseekV3: return "DeepSeek V3.2"
        case .qwen35Plus: return "Qwen3.5-Plus"
        case .minimaxM25: return "MiniMax M2.5"
        case .glm5: return "GLM-5"
        }
    }
    
    static let defaultModel: AvailableModel = .deepseekV3
}

// MARK: - Message Model

struct Message: Codable, Equatable {
    let role: String
    var content: String

    enum Role: String {
        case system = "system"
        case user = "user"
        case assistant = "assistant"
    }

    init(role: Role, content: String) {
        self.role = role.rawValue
        self.content = content
    }
}

// MARK: - Chat Settings

struct ChatSettings: Equatable {
    var model: String
    var temperature: Double
    var topP: Double
    var stream: Bool
    var systemPrompt: String

    static let `default` = ChatSettings(
        model: AvailableModel.defaultModel.rawValue,
        temperature: 0.7,
        topP: 0.9,
        stream: true,
        systemPrompt: "You are a helpful assistant."
    )
}

// MARK: - API Request/Response Models

struct ChatRequest: Codable {
    let model: String
    let messages: [Message]
    let stream: Bool
    let temperature: Double
    let top_p: Double
    
    init(settings: ChatSettings, messages: [Message]) {
        self.model = settings.model
        self.messages = messages
        self.stream = settings.stream
        self.temperature = settings.temperature
        self.top_p = settings.topP
    }
}

struct ChatResponse: Codable {
    let id: String?
    let model: String?
    let choices: [Choice]?
    let created: Int?
    
    struct Choice: Codable {
        let index: Int?
        let message: Message?
        let delta: Delta?
        let finish_reason: String?
    }
    
    struct Delta: Codable {
        let role: String?
        let content: String?
    }
    
    var content: String? {
        choices?.first?.message?.content ?? choices?.first?.delta?.content
    }
}

// MARK: - Chat State

enum ChatState {
    case idle
    case loading
    case error(String)
}

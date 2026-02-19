import Foundation

// MARK: - Logger

struct Logger {
    static let shared = Logger()
    
    // Флаг для включения/отключения логирования
    var isEnabled: Bool = true
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
    
    func log(_ message: String, type: LogType = .info) {
        guard isEnabled else { return }
        
        let timestamp = dateFormatter.string(from: Date())
        let emoji: String
        switch type {
        case .info: emoji = "ℹ️"
        case .request: emoji = "📤"
        case .response: emoji = "📥"
        case .error: emoji = "❌"
        case .stream: emoji = "🔄"
        }
        print("[\(timestamp)] \(emoji) \(message)")
    }
    
    enum LogType {
        case info
        case request
        case response
        case error
        case stream
    }
}

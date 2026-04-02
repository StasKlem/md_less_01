//
//  Message.swift
//  SupportBot
//
//  Created by Stas Klem on 02.04.2026.
//

import Foundation

/// Сообщение чата
struct Message: Codable, Identifiable {
    let id: UUID
    let text: String
    let sender: Sender
    let timestamp: Date
    
    init(id: UUID = UUID(), text: String, sender: Sender, timestamp: Date = Date()) {
        self.id = id
        self.text = text
        self.sender = sender
        self.timestamp = timestamp
    }
    
    /// Форматированное время для отображения
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: timestamp)
    }
    
    /// Форматированная дата для хранения
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}

/// Отправитель сообщения
enum Sender: String, Codable {
    case user
    case bot
    
    var displayName: String {
        switch self {
        case .user: return "Вы"
        case .bot: return "SupportBot"
        }
    }
    
    var emoji: String {
        switch self {
        case .user: return "🔵"
        case .bot: return "🟢"
        }
    }
}

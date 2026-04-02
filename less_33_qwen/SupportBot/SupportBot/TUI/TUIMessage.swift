//
//  TUIMessage.swift
//  SupportBot
//
//  Created by Stas Klem on 02.04.2026.
//

import Foundation

/// Сообщение для TUI (локальная модель)
struct TUIMessage {
    let id: UUID
    let text: String
    let sender: TUISender
    let timestamp: Date

    init(text: String, sender: TUISender) {
        self.id = UUID()
        self.text = text
        self.sender = sender
        self.timestamp = Date()
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: timestamp)
    }
}

/// Отправитель сообщения для TUI
enum TUISender {
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

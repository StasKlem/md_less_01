//
//  ChatSession.swift
//  SupportBot
//
//  Created by Stas Klem on 02.04.2026.
//

import Foundation

/// Сессия чата
struct ChatSession: Codable, Identifiable {
    let id: String
    let createdAt: Date
    let lastActivityAt: Date
    let ticketData: TicketData?
    
    init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        lastActivityAt: Date = Date(),
        ticketData: TicketData? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.ticketData = ticketData
    }
}

/// Данные тикета (опционально)
struct TicketData: Codable {
    let id: String
    let subject: String?
    let status: String
    let priority: String
    
    init(
        id: String,
        subject: String? = nil,
        status: String = "open",
        priority: String = "normal"
    ) {
        self.id = id
        self.subject = subject
        self.status = status
        self.priority = priority
    }
}

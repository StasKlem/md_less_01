//
//  SummarizationStrategy.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 26.02.2026.
//

import Foundation

enum SummarizationStrategy: Codable, Equatable {
    case none
    case keepLastMessages(Int)
    case windowLastMessages(Int)

    var displayName: String {
        switch self {
        case .none:
            return "Без суммаризации"
        case .keepLastMessages(let count):
            return "Хранить \(count) последних сообщений"
        case .windowLastMessages(let count):
            return "Окно последних \(count) сообщений"
        }
    }

    static let defaultCount = 10
}

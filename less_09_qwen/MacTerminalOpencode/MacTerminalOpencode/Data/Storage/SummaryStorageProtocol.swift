//
//  SummaryStorageProtocol.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 26.02.2026.
//

import Foundation

/// Protocol for summary storage
protocol SummaryStorageProtocol {
    func saveSummary(_ summary: String)
    func loadSummary() -> String?
    func clearSummary()
}

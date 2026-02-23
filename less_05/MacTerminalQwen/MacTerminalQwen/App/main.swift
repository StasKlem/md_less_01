//
//  main.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import AppKit

/// Точка входа приложения с явным main().
/// Даёт полный контроль над инициализацией приложения.

// Создаём приложение
let app = NSApplication.shared

// Создаём делегата
let delegate = AppDelegate()
app.delegate = delegate

// Запускаем приложение
app.run()

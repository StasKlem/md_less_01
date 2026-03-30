//
//  main.swift
//  LightNeiroClient
//
//  Created by Stas Klem on 28.02.2026.
//

import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()

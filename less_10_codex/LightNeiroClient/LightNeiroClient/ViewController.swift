//
//  ViewController.swift
//  LightNeiroClient
//
//  Created by Stas Klem on 28.02.2026.
//

import Cocoa

class ViewController: NSViewController {
    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "LightNeiroClient")
        label.font = NSFont.systemFont(ofSize: 28, weight: .semibold)
        label.alignment = .center
        return label
    }()

    private let subtitleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "UI is built programmatically without storyboard")
        label.font = NSFont.systemFont(ofSize: 15, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        return label
    }()

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
    }

    private func setupLayout() {
        let stack = NSStackView(views: [titleLabel, subtitleLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
    }
}

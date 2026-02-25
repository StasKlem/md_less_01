//
//  MetricsPanelViewController.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 22.02.2026.
//

import AppKit

/// Metrics panel displaying real-time request statistics
final class MetricsPanelViewController: NSViewController {

    private let metricsLabel: NSTextField = {
        let field = NSTextField()
        field.isEditable = false
        field.isSelectable = true
        field.isBezeled = false
        field.drawsBackground = false
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 0
        return field
    }()

    private let stackView = NSStackView()

    private var viewModel: MetricsViewModel?

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 150))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        resetDisplay()
    }

    // MARK: - Configuration

    func configure(with viewModel: MetricsViewModel) {
        self.viewModel = viewModel

        viewModel.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleViewModelEvent(event)
            }
        }
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.spacing = 8
        stackView.alignment = .leading
        view.addSubview(stackView)

        let titleLabel = NSTextField(labelWithString: "Request Metrics")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        stackView.addArrangedSubview(titleLabel)

        stackView.addArrangedSubview(metricsLabel)

        setupConstraints()
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }

    // MARK: - ViewModel Events

    private func handleViewModelEvent(_ event: MetricsViewModelEvent) {
        print("[MetricsPanel] Received event: \(event)")
        switch event {
        case .metricsUpdated(let metrics):
            updateMetricsDisplay(metrics)
        case .reset:
            resetDisplay()
        }
    }

    private func updateMetricsDisplay(_ metrics: RequestMetrics) {
        print("[MetricsPanel] Updating display - model: \(metrics.modelName), tokens: \(metrics.completionTokens), speed: \(metrics.tokensPerSecond), duration: \(metrics.requestDuration)")
        
        let modelName = metrics.modelName.isEmpty ? "-" : metrics.modelName
        metricsLabel.stringValue = """
            Model: \(modelName)
            
            Current Request:
            • Prompt: \(metrics.promptTokens) tok
            • Completion: \(metrics.completionTokens) tok
            • Total: \(metrics.totalTokens) tok
            • Speed: \(String(format: "%.1f", metrics.tokensPerSecond)) tok/s
            • Duration: \(String(format: "%.1f", metrics.requestDuration))s
            
            Conversation Total:
            • Prompt: \(metrics.conversationPromptTokens) tok
            • Completion: \(metrics.conversationCompletionTokens) tok
            • Total: \(metrics.conversationTotalTokens) tok
            """
    }

    private func resetDisplay() {
        metricsLabel.stringValue = """
            Model: -
            
            Current Request:
            • Prompt: 0 tok
            • Completion: 0 tok
            • Total: 0 tok
            • Speed: 0.0 tok/s
            • Duration: 0.0s
            
            Conversation Total:
            • Prompt: 0 tok
            • Completion: 0 tok
            • Total: 0 tok
            """
    }
}

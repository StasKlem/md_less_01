//
//  MetricsPanelViewController.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 22.02.2026.
//

import AppKit

/// Metrics panel displaying real-time request statistics
final class MetricsPanelViewController: NSViewController {
    
    private let modelNameLabel: NSTextField = {
        let field = NSTextField()
        field.isEditable = false
        field.isSelectable = true
        field.isBezeled = false
        field.drawsBackground = false
        field.stringValue = "Model: -"
        return field
    }()
    
    private let tokensLabel: NSTextField = {
        let field = NSTextField()
        field.isEditable = false
        field.isSelectable = true
        field.isBezeled = false
        field.drawsBackground = false
        field.stringValue = "Tokens: 0"
        return field
    }()
    
    private let speedLabel: NSTextField = {
        let field = NSTextField()
        field.isEditable = false
        field.isSelectable = true
        field.isBezeled = false
        field.drawsBackground = false
        field.stringValue = "Speed: 0 tok/s"
        return field
    }()
    
    private let durationLabel: NSTextField = {
        let field = NSTextField()
        field.isEditable = false
        field.isSelectable = true
        field.isBezeled = false
        field.drawsBackground = false
        field.stringValue = "Duration: 0.0s"
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
        stackView.distribution = .fillEqually
        view.addSubview(stackView)
        
        let titleLabel = NSTextField(labelWithString: "Request Metrics")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        stackView.addArrangedSubview(titleLabel)
        
        stackView.addArrangedSubview(modelNameLabel)
        stackView.addArrangedSubview(tokensLabel)
        stackView.addArrangedSubview(speedLabel)
        stackView.addArrangedSubview(durationLabel)
        
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
        modelNameLabel.stringValue = "Model: \(metrics.modelName.isEmpty ? "-" : metrics.modelName)"
        tokensLabel.stringValue = "Tokens: \(metrics.completionTokens)"
        speedLabel.stringValue = String(format: "Speed: %.1f tok/s", metrics.tokensPerSecond)
        durationLabel.stringValue = String(format: "Duration: %.1fs", metrics.requestDuration)
    }
    
    private func resetDisplay() {
        modelNameLabel.stringValue = "Model: -"
        tokensLabel.stringValue = "Tokens: 0"
        speedLabel.stringValue = "Speed: 0 tok/s"
        durationLabel.stringValue = "Duration: 0.0s"
    }
}

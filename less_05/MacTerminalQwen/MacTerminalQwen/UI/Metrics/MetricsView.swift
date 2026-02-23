//
//  MetricsView.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import AppKit

/// Вид для отображения метрик запроса.
final class MetricsView: NSView {
    
    // MARK: - Properties
    
    // Labels
    private let modelLabel = createValueLabel()
    private let speedLabel = createValueLabel()
    private let tokensLabel = createValueLabel()
    private let durationLabel = createValueLabel()
    private let avgSpeedLabel = createValueLabel()
    
    // Activity Indicator
    private let activityIndicator = NSProgressIndicator()
    
    // Status Label
    private let statusLabel = NSTextField(labelWithString: "Ожидание запроса...")
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
        setupLayout()
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    
    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
    
    private func setupLayout() {
        let margin: CGFloat = 12
        let spacing: CGFloat = 8
        let labelHeight: CGFloat = 20
        
        // Status
        statusLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Activity Indicator
        activityIndicator.style = .spinning
        activityIndicator.controlSize = .small
        activityIndicator.isDisplayedWhenStopped = false
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        // Headers
        let modelHeader = MetricsView.createHeaderLabel("Модель:")
        let speedHeader = MetricsView.createHeaderLabel("Скорость:")
        let tokensHeader = MetricsView.createHeaderLabel("Токены:")
        let durationHeader = MetricsView.createHeaderLabel("Длительность:")
        let avgSpeedHeader = MetricsView.createHeaderLabel("Средняя скорость:")
        
        // Добавляем все элементы
        [statusLabel, activityIndicator,
         modelHeader, modelLabel,
         speedHeader, speedLabel,
         tokensHeader, tokensLabel,
         durationHeader, durationLabel,
         avgSpeedHeader, avgSpeedLabel].forEach {
            addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        
        NSLayoutConstraint.activate([
            // Status
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            statusLabel.topAnchor.constraint(equalTo: topAnchor, constant: margin),
            
            // Activity Indicator
            activityIndicator.leadingAnchor.constraint(equalTo: statusLabel.trailingAnchor, constant: spacing),
            activityIndicator.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            activityIndicator.widthAnchor.constraint(equalToConstant: 16),
            activityIndicator.heightAnchor.constraint(equalToConstant: 16),
            
            // Model
            modelHeader.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            modelHeader.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: spacing * 2),
            modelHeader.widthAnchor.constraint(equalToConstant: 120),
            
            modelLabel.leadingAnchor.constraint(equalTo: modelHeader.trailingAnchor, constant: spacing),
            modelLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            modelLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: spacing * 2),
            modelLabel.heightAnchor.constraint(equalToConstant: labelHeight),
            
            // Speed
            speedHeader.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            speedHeader.topAnchor.constraint(equalTo: modelLabel.bottomAnchor, constant: spacing),
            speedHeader.widthAnchor.constraint(equalToConstant: 120),
            
            speedLabel.leadingAnchor.constraint(equalTo: speedHeader.trailingAnchor, constant: spacing),
            speedLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            speedLabel.topAnchor.constraint(equalTo: modelLabel.bottomAnchor, constant: spacing),
            speedLabel.heightAnchor.constraint(equalToConstant: labelHeight),
            
            // Tokens
            tokensHeader.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            tokensHeader.topAnchor.constraint(equalTo: speedLabel.bottomAnchor, constant: spacing),
            tokensHeader.widthAnchor.constraint(equalToConstant: 120),
            
            tokensLabel.leadingAnchor.constraint(equalTo: tokensHeader.trailingAnchor, constant: spacing),
            tokensLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            tokensLabel.topAnchor.constraint(equalTo: speedLabel.bottomAnchor, constant: spacing),
            tokensLabel.heightAnchor.constraint(equalToConstant: labelHeight),
            
            // Duration
            durationHeader.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            durationHeader.topAnchor.constraint(equalTo: tokensLabel.bottomAnchor, constant: spacing),
            durationHeader.widthAnchor.constraint(equalToConstant: 120),
            
            durationLabel.leadingAnchor.constraint(equalTo: durationHeader.trailingAnchor, constant: spacing),
            durationLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            durationLabel.topAnchor.constraint(equalTo: tokensLabel.bottomAnchor, constant: spacing),
            durationLabel.heightAnchor.constraint(equalToConstant: labelHeight),
            
            // Avg Speed
            avgSpeedHeader.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            avgSpeedHeader.topAnchor.constraint(equalTo: durationLabel.bottomAnchor, constant: spacing),
            avgSpeedHeader.widthAnchor.constraint(equalToConstant: 120),
            
            avgSpeedLabel.leadingAnchor.constraint(equalTo: avgSpeedHeader.trailingAnchor, constant: spacing),
            avgSpeedLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            avgSpeedLabel.topAnchor.constraint(equalTo: durationLabel.bottomAnchor, constant: spacing),
            avgSpeedLabel.heightAnchor.constraint(equalToConstant: labelHeight)
        ])
    }
    
    // MARK: - Public Methods
    
    func updateMetrics(_ metrics: RequestMetrics, isActive: Bool) {
        modelLabel.stringValue = metrics.modelName ?? "—"
        speedLabel.stringValue = metrics.formattedSpeed
        tokensLabel.stringValue = metrics.hasTokenData
            ? "\(metrics.totalTokens) (prompt: \(metrics.promptTokens), completion: \(metrics.completionTokens))"
            : "—"
        durationLabel.stringValue = metrics.formattedDuration
        
        // Activity indicator
        if isActive {
            activityIndicator.startAnimation(nil)
            statusLabel.stringValue = "Генерация..."
            statusLabel.textColor = .controlAccentColor
        } else {
            activityIndicator.stopAnimation(nil)
            statusLabel.stringValue = metrics.hasTokenData ? "Завершено" : "Ожидание запроса..."
            statusLabel.textColor = .secondaryLabelColor
        }
    }
    
    func updateAverageSpeed(_ speed: String) {
        avgSpeedLabel.stringValue = speed
    }
    
    func reset() {
        modelLabel.stringValue = "—"
        speedLabel.stringValue = "—"
        tokensLabel.stringValue = "—"
        durationLabel.stringValue = "—"
        statusLabel.stringValue = "Ожидание запроса..."
        activityIndicator.stopAnimation(nil)
    }
}

// MARK: - Factory Methods

private extension MetricsView {
    static func createValueLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "—")
        label.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        label.textColor = .textColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
    
    static func createHeaderLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
}

private func createValueLabel() -> NSTextField {
    let label = NSTextField(labelWithString: "—")
    label.font = NSFont.systemFont(ofSize: 12, weight: .regular)
    label.textColor = .textColor
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
}

private func createHeaderLabel(_ text: String) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
    label.textColor = .secondaryLabelColor
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
}

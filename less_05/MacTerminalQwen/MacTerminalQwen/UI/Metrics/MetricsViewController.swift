//
//  MetricsViewController.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import AppKit
import Combine

/// Контроллер для управления видом метрик.
final class MetricsViewController: NSViewController {
    
    // MARK: - Properties
    
    let viewModel: MetricsViewModel
    
    private let metricsView = MetricsView()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(viewModel: MetricsViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func loadView() {
        view = NSView()
        view.frame = NSRect(x: 0, y: 0, width: 300, height: 150)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupMetricsView()
        setupBindings()
    }
    
    // MARK: - Setup
    
    private func setupMetricsView() {
        view.addSubview(metricsView)
        metricsView.fillSuperview()
    }
    
    private func setupBindings() {
        // Подписка на метрики
        viewModel.$metrics
            .combineLatest(viewModel.$isActive)
            .receive(on: RunLoop.main)
            .sink { [weak self] metrics, isActive in
                self?.metricsView.updateMetrics(metrics, isActive: isActive)
            }
            .store(in: &cancellables)
        
        // Подписка на streaming progress
        viewModel.$streamingProgress
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // Обновление уже происходит через метрики
            }
            .store(in: &cancellables)
        
        // Подписка на историю для средней скорости
        viewModel.$history
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.metricsView.updateAverageSpeed(self?.viewModel.formattedAverageSpeed ?? "—")
            }
            .store(in: &cancellables)
    }
}

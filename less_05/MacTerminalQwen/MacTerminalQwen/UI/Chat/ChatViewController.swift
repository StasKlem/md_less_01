//
//  ChatViewController.swift
//  MacTerminalQwen
//
//  Created by Stas Klem on 22.02.2026.
//

import AppKit
import Combine

/// Контроллер для управления видом чата.
final class ChatViewController: NSViewController {
    
    // MARK: - Properties
    
    let viewModel: ChatViewModel
    
    private let chatView = ChatView()
    private let inputView = MessageInputView()
    private let emptyStateLabel: NSTextField
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
        self.emptyStateLabel = NSTextField(labelWithString: "Начните новый диалог")
        super.init(nibName: nil, bundle: nil)
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func loadView() {
        view = NSView()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        setupEmptyStateLabel()
        setupInputView()  // Сначала создаём inputView
        setupChatView()   // Потом chatView с ограничением к inputView


        setupBindings()
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        Task { @MainActor in
            inputView.focus()
        }
    }
    
    // MARK: - Setup
    
    private func setupEmptyStateLabel() {
        emptyStateLabel.font = NSFont.systemFont(ofSize: 18, weight: .light)
        emptyStateLabel.textColor = .placeholderTextColor
        emptyStateLabel.alignment = .center
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
    }
    
    private func setupChatView() {
        view.addSubview(chatView)
        chatView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            chatView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chatView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chatView.topAnchor.constraint(equalTo: view.topAnchor),
            chatView.bottomAnchor.constraint(equalTo: inputView.topAnchor, constant: -8)
        ])
    }
    
    private func setupInputView() {
        view.addSubview(inputView)
        inputView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            inputView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            inputView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            inputView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
//            inputView.topAnchor.constraint(equalTo: chatView.bottomAnchor, constant: 8),
            inputView.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        inputView.onSend = { [weak self] in
            self?.viewModel.sendMessage()
        }
        
        inputView.onCancel = { [weak self] in
            self?.viewModel.cancelRequest()
        }
    }
    
    private func setupBindings() {
        // Подписка на сообщения
        viewModel.$messages
            .receive(on: RunLoop.main)
            .sink { [weak self] messages in
                self?.chatView.updateMessages(messages)
                self?.updateEmptyStateVisibility()
            }
            .store(in: &cancellables)
        
        // Подписка на isLoading
        viewModel.$isLoading
            .receive(on: RunLoop.main)
            .sink { [weak self] isLoading in
                self?.inputView.isLoading = isLoading
            }
            .store(in: &cancellables)
        
        // Подписка на inputText (двусторонняя связь)
        viewModel.$inputText
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                if self?.inputView.text != text {
                    self?.inputView.text = text
                }
            }
            .store(in: &cancellables)
        
        // Подписка на ошибку
        viewModel.$error
            .receive(on: RunLoop.main)
            .sink { [weak self] error in
                if let error = error {
                    self?.showError(error)
                }
            }
            .store(in: &cancellables)
        
        // Подписка на метрики
        viewModel.$currentMetrics
            .receive(on: RunLoop.main)
            .sink { [weak self] metrics in
                self?.notifyMetricsChanged(metrics)
            }
            .store(in: &cancellables)
        
        // Подписка на streaming progress
        viewModel.$streamingProgress
            .receive(on: RunLoop.main)
            .sink { [weak self] progress in
                self?.notifyStreamingProgressChanged(progress)
            }
            .store(in: &cancellables)
    }
    
    private func updateEmptyStateVisibility() {
        let isEmpty = viewModel.messages.isEmpty
        
        if isEmpty && emptyStateLabel.superview == nil {
            view.addSubview(emptyStateLabel)
            NSLayoutConstraint.activate([
                emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50)
            ])
        } else if !isEmpty && emptyStateLabel.superview != nil {
            emptyStateLabel.removeFromSuperview()
        }
        
        emptyStateLabel.isHidden = !isEmpty
    }
    
    private func showError(_ error: AppError) {
        let alert = NSAlert(error: error)
        alert.alertStyle = .warning
        alert.beginSheetModal(for: view.window!) { _ in
            // Dismiss
        }
    }
    
    private func notifyMetricsChanged(_ metrics: RequestMetrics) {
        // Уведомить родительский контроллер о изменении метрик
        if let splitVC = parent as? MainSplitViewController,
           let metricsVC = splitVC.metricsViewController as? MetricsViewController {
            metricsVC.viewModel.updateMetrics(metrics)
        }
    }

    private func notifyStreamingProgressChanged(_ progress: StreamingProgress) {
        // Уведомить родительский контроллер о прогрессе
        if let splitVC = parent as? MainSplitViewController,
           let metricsVC = splitVC.metricsViewController as? MetricsViewController {
            Task { @MainActor in
                metricsVC.viewModel.updateStreamingProgress(progress)
            }
        }
    }
}

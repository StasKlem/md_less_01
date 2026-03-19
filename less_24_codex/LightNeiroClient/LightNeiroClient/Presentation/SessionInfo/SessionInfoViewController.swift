import Cocoa
import Combine

final class SessionInfoViewController: NSViewController {
    private let viewModel: SessionInfoViewModel
    private var cancellables = Set<AnyCancellable>()

    private let inputTokensLabel = NSTextField(labelWithString: "Input tokens: 0")
    private let outputTokensLabel = NSTextField(labelWithString: "Output tokens: 0")
    private let requestsLabel = NSTextField(labelWithString: "Requests: 0")
    private let latencyLabel = NSTextField(labelWithString: "Last latency: 0 ms")

    init(viewModel: SessionInfoViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bind()
        viewModel.refresh()
    }

    private func setupUI() {
        let title = NSTextField(labelWithString: "Session info")
        title.font = .systemFont(ofSize: 14, weight: .semibold)

        let stack = NSStackView(views: [
            title,
            inputTokensLabel,
            outputTokensLabel,
            requestsLabel,
            latencyLabel
        ])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
        ])
    }

    private func bind() {
        viewModel.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.inputTokensLabel.stringValue = "Input tokens: \(snapshot.totalInputTokens)"
                self?.outputTokensLabel.stringValue = "Output tokens: \(snapshot.totalOutputTokens)"
                self?.requestsLabel.stringValue = "Requests: \(snapshot.totalRequests)"
                self?.latencyLabel.stringValue = "Last latency: \(snapshot.lastLatencyMs) ms"
            }
            .store(in: &cancellables)
    }
}

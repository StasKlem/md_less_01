import Cocoa

class PlaceholderViewController: NSViewController {
    private let screenTitle: String
    private let screenSubtitle: String
    private let backgroundColor: NSColor

    init(
        title: String,
        subtitle: String,
        backgroundColor: NSColor = .windowBackgroundColor
    ) {
        self.screenTitle = title
        self.screenSubtitle = subtitle
        self.backgroundColor = backgroundColor
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = backgroundColor.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupContent()
    }

    private func setupContent() {
        let titleLabel = NSTextField(labelWithString: screenTitle)
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.alignment = .center

        let subtitleLabel = NSTextField(labelWithString: screenSubtitle)
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.maximumNumberOfLines = 0
        subtitleLabel.lineBreakMode = .byWordWrapping

        let stack = NSStackView(views: [titleLabel, subtitleLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
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

final class SettingsViewController: PlaceholderViewController {
    init() {
        super.init(
            title: "Настройки",
            subtitle: "Все настройки удалены. Экран оставлен как каркас."
        )
    }
}

final class InvariantsSettingsViewController: PlaceholderViewController {
    init() {
        super.init(
            title: "Инварианты",
            subtitle: "Это место под будущие настройки планировщика."
        )
    }
}

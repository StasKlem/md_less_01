import AppKit
import Foundation

protocol DialogCollectionCellProtocol where Self: NSCollectionViewItem {
    func apply(_ state: DialogHistoryItemViewState)
    func updateVisibleState(_ state: DialogHistoryItemViewState)
}

class BaseMessageCollectionItem: NSCollectionViewItem, DialogCollectionCellProtocol {
    private enum UI {
        static let profileSeparator = "\n\n"
    }

    private let bubbleView = NSView()
    private let contentStack = NSStackView()
    private let textLabel = NSTextField(wrappingLabelWithString: "")
    private let assistantContentStack = NSStackView()
    private let assistantAnswerLabel = NSTextField(wrappingLabelWithString: "")
    private let assistantEvidenceStack = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "")

    private var currentState: DialogHistoryItemViewState?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true

        bubbleView.wantsLayer = true
        bubbleView.layer?.cornerRadius = 10
        bubbleView.translatesAutoresizingMaskIntoConstraints = false

        contentStack.orientation = .vertical
        contentStack.spacing = 8
        contentStack.alignment = .leading
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.maximumNumberOfLines = 0
        textLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        textLabel.setContentHuggingPriority(.required, for: .vertical)

        assistantContentStack.orientation = .vertical
        assistantContentStack.spacing = 8
        assistantContentStack.alignment = .leading
        assistantContentStack.translatesAutoresizingMaskIntoConstraints = false

        assistantAnswerLabel.translatesAutoresizingMaskIntoConstraints = false
        assistantAnswerLabel.maximumNumberOfLines = 0
        assistantAnswerLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        assistantAnswerLabel.setContentHuggingPriority(.required, for: .vertical)

        assistantEvidenceStack.orientation = .vertical
        assistantEvidenceStack.spacing = 8
        assistantEvidenceStack.alignment = .leading
        assistantEvidenceStack.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor

        view.addSubview(bubbleView)
        bubbleView.addSubview(contentStack)
        bubbleView.addSubview(statusLabel)

        contentStack.addArrangedSubview(textLabel)
        contentStack.addArrangedSubview(assistantContentStack)

        assistantContentStack.addArrangedSubview(assistantAnswerLabel)
        assistantContentStack.addArrangedSubview(assistantEvidenceStack)

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: view.topAnchor),
            bubbleView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bubbleView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bubbleView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            contentStack.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10),
            contentStack.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 10),
            contentStack.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -10),

            textLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            assistantContentStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            assistantAnswerLabel.widthAnchor.constraint(equalTo: assistantContentStack.widthAnchor),
            assistantEvidenceStack.widthAnchor.constraint(equalTo: assistantContentStack.widthAnchor),

            statusLabel.topAnchor.constraint(equalTo: contentStack.bottomAnchor, constant: 6),
            statusLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -10),
            statusLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8),
        ])

        assistantContentStack.isHidden = true
    }

    func apply(_ state: DialogHistoryItemViewState) {
        currentState = state
        configureContent(for: state)
        statusLabel.stringValue = statusText(for: state.status)
        applyStyle(for: state)
    }

    func updateVisibleState(_ state: DialogHistoryItemViewState) {
        guard currentState?.id == state.id else {
            apply(state)
            return
        }

        currentState = state
        configureContent(for: state)
        statusLabel.stringValue = statusText(for: state.status)
    }

    func applyStyle(for state: DialogHistoryItemViewState) {
        switch state.kind {
        case .user:
            bubbleView.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.22).cgColor
        case .assistant:
            bubbleView.layer?.backgroundColor = NSColor.systemGray.withAlphaComponent(0.18).cgColor
        case .system:
            switch state.tone {
            case .normal:
                bubbleView.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.20).cgColor
            case .stateTransition:
                bubbleView.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.18).cgColor
            }
        }
    }

    private func statusText(for status: DialogMessageStatus) -> String {
        switch status {
        case .sending:
            return "sending"
        case .streaming:
            return "streaming"
        case .sent:
            return "sent"
        case .failed:
            return "failed"
        }
    }

    private func makeAttributedMessage(for state: DialogHistoryItemViewState) -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: textLabel.font as Any,
            .foregroundColor: NSColor.labelColor
        ]
        let result = NSMutableAttributedString(string: state.text, attributes: attributes)

        guard state.kind == .user else {
            return result
        }
        guard let separatorRange = state.text.range(of: UI.profileSeparator),
              separatorRange.lowerBound > state.text.startIndex else {
            return result
        }

        let profilePrefix = String(state.text[..<separatorRange.lowerBound])
        let range = NSRange(location: 0, length: (profilePrefix as NSString).length)
        result.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: range)
        return result
    }

    private func configureContent(for state: DialogHistoryItemViewState) {
        guard state.kind == .assistant else {
            assistantContentStack.isHidden = true
            clearAssistantEvidenceViews()
            textLabel.isHidden = false
            textLabel.attributedStringValue = makeAttributedMessage(for: state)
            return
        }

        let parsed = parseAssistantContent(state.text)
        textLabel.isHidden = true
        assistantContentStack.isHidden = false
        assistantAnswerLabel.stringValue = parsed.answer
        rebuildAssistantEvidenceViews(parsed.evidences)
    }

    private func parseAssistantContent(_ text: String) -> (answer: String, evidences: [AssistantEvidence]) {
        let paragraphs = text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let first = paragraphs.first else {
            return (answer: text, evidences: [])
        }

        let evidences: [AssistantEvidence] = paragraphs.dropFirst().compactMap { paragraph in
            let lines = paragraph
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard lines.count >= 2 else { return nil }
            return AssistantEvidence(
                source: lines[0],
                quote: lines.dropFirst().joined(separator: "\n")
            )
        }
        return (answer: first, evidences: evidences)
    }

    private func rebuildAssistantEvidenceViews(_ evidences: [AssistantEvidence]) {
        clearAssistantEvidenceViews()

        guard !evidences.isEmpty else {
            assistantEvidenceStack.isHidden = true
            return
        }

        assistantEvidenceStack.isHidden = false
        for evidence in evidences {
            let view = AssistantEvidenceCardView()
            view.configure(source: evidence.source, quote: evidence.quote)
            assistantEvidenceStack.addArrangedSubview(view)
        }
    }

    private func clearAssistantEvidenceViews() {
        for arranged in assistantEvidenceStack.arrangedSubviews {
            assistantEvidenceStack.removeArrangedSubview(arranged)
            arranged.removeFromSuperview()
        }
    }
}

final class UserMessageCollectionItem: BaseMessageCollectionItem {}
final class AssistantMessageCollectionItem: BaseMessageCollectionItem {}
final class SystemMessageCollectionItem: BaseMessageCollectionItem {}

private struct AssistantEvidence {
    let source: String
    let quote: String
}

private final class AssistantEvidenceCardView: NSView {
    private let sourceLabel = NSTextField(wrappingLabelWithString: "")
    private let quoteLabel = NSTextField(wrappingLabelWithString: "")
    private let stackView = NSStackView()
    private let sourceContainer = NSView()
    private let quoteContainer = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(source: String, quote: String) {
        sourceLabel.stringValue = source
        quoteLabel.stringValue = quote
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.systemGray.withAlphaComponent(0.12).cgColor
        translatesAutoresizingMaskIntoConstraints = false

        sourceLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        sourceLabel.textColor = .labelColor
        sourceLabel.maximumNumberOfLines = 0
        sourceLabel.translatesAutoresizingMaskIntoConstraints = false
        sourceLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        sourceLabel.setContentHuggingPriority(.required, for: .vertical)

        quoteLabel.font = .systemFont(ofSize: 12, weight: .regular)
        quoteLabel.textColor = .labelColor
        quoteLabel.maximumNumberOfLines = 0
        quoteLabel.translatesAutoresizingMaskIntoConstraints = false
        quoteLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        quoteLabel.setContentHuggingPriority(.required, for: .vertical)

        sourceContainer.wantsLayer = true
        sourceContainer.layer?.cornerRadius = 6
        sourceContainer.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.20).cgColor
        sourceContainer.translatesAutoresizingMaskIntoConstraints = false

        quoteContainer.wantsLayer = true
        quoteContainer.layer?.cornerRadius = 6
        quoteContainer.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.26).cgColor
        quoteContainer.translatesAutoresizingMaskIntoConstraints = false

        stackView.orientation = .vertical
        stackView.spacing = 4
        stackView.alignment = .leading
        stackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stackView)
        stackView.addArrangedSubview(sourceContainer)
        stackView.addArrangedSubview(quoteContainer)
        sourceContainer.addSubview(sourceLabel)
        quoteContainer.addSubview(quoteLabel)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            sourceContainer.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            quoteContainer.widthAnchor.constraint(equalTo: stackView.widthAnchor),

            sourceLabel.topAnchor.constraint(equalTo: sourceContainer.topAnchor, constant: 6),
            sourceLabel.leadingAnchor.constraint(equalTo: sourceContainer.leadingAnchor, constant: 6),
            sourceLabel.trailingAnchor.constraint(equalTo: sourceContainer.trailingAnchor, constant: -6),
            sourceLabel.bottomAnchor.constraint(equalTo: sourceContainer.bottomAnchor, constant: -6),

            quoteLabel.topAnchor.constraint(equalTo: quoteContainer.topAnchor, constant: 6),
            quoteLabel.leadingAnchor.constraint(equalTo: quoteContainer.leadingAnchor, constant: 6),
            quoteLabel.trailingAnchor.constraint(equalTo: quoteContainer.trailingAnchor, constant: -6),
            quoteLabel.bottomAnchor.constraint(equalTo: quoteContainer.bottomAnchor, constant: -6)
        ])
    }
}

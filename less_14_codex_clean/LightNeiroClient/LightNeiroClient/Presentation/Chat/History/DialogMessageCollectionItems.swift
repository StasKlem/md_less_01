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
    private let textLabel = NSTextField(wrappingLabelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")

    private var currentState: DialogHistoryItemViewState?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true

        bubbleView.wantsLayer = true
        bubbleView.layer?.cornerRadius = 10
        bubbleView.translatesAutoresizingMaskIntoConstraints = false

        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.maximumNumberOfLines = 0

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor

        view.addSubview(bubbleView)
        bubbleView.addSubview(textLabel)
        bubbleView.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: view.topAnchor),
            bubbleView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bubbleView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bubbleView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            textLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10),
            textLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 10),
            textLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -10),

            statusLabel.topAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: 6),
            statusLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -10),
            statusLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8),
        ])
    }

    func apply(_ state: DialogHistoryItemViewState) {
        currentState = state
        textLabel.attributedStringValue = makeAttributedMessage(for: state)
        statusLabel.stringValue = statusText(for: state.status)
        applyStyle(for: state)
    }

    func updateVisibleState(_ state: DialogHistoryItemViewState) {
        guard currentState?.id == state.id else {
            apply(state)
            return
        }

        currentState = state
        textLabel.attributedStringValue = makeAttributedMessage(for: state)
        statusLabel.stringValue = statusText(for: state.status)
    }

    func applyStyle(for state: DialogHistoryItemViewState) {
        switch state.kind {
        case .user:
            bubbleView.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.22).cgColor
        case .assistant:
            bubbleView.layer?.backgroundColor = NSColor.systemGray.withAlphaComponent(0.18).cgColor
        case .system:
            bubbleView.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.20).cgColor
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
}

final class UserMessageCollectionItem: BaseMessageCollectionItem {}
final class AssistantMessageCollectionItem: BaseMessageCollectionItem {}
final class SystemMessageCollectionItem: BaseMessageCollectionItem {}

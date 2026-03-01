import AppKit
import Foundation

enum DialogMessageKind: Hashable {
    case user
    case assistant
    case system
}

enum DialogMessageStatus: Hashable {
    case sending
    case streaming
    case sent
    case failed
}

struct DialogHistoryItemViewState: Hashable {
    let id: UUID
    let kind: DialogMessageKind
    let text: String
    let status: DialogMessageStatus
    let createdAt: Date

    init(
        id: UUID = UUID(),
        kind: DialogMessageKind,
        text: String,
        status: DialogMessageStatus,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.status = status
        self.createdAt = createdAt
    }
}

struct DialogHistoryPatch {
    let id: UUID
    let state: DialogHistoryItemViewState
}

struct DialogCellDescriptor {
    let kind: DialogMessageKind
    let reuseIdentifier: NSUserInterfaceItemIdentifier
    let itemClass: NSCollectionViewItem.Type
}

struct DialogHistoryConfig {
    let contentInsets: NSEdgeInsets
    let lineSpacing: CGFloat
    let interitemSpacing: CGFloat
    let animateChanges: Bool
    let cellDescriptors: [DialogMessageKind: DialogCellDescriptor]

    static let `default` = DialogHistoryConfig(
        contentInsets: NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8),
        lineSpacing: 8,
        interitemSpacing: 8,
        animateChanges: true,
        cellDescriptors: [
            .user: DialogCellDescriptor(
                kind: .user,
                reuseIdentifier: NSUserInterfaceItemIdentifier("UserMessageCollectionItem"),
                itemClass: UserMessageCollectionItem.self
            ),
            .assistant: DialogCellDescriptor(
                kind: .assistant,
                reuseIdentifier: NSUserInterfaceItemIdentifier("AssistantMessageCollectionItem"),
                itemClass: AssistantMessageCollectionItem.self
            ),
            .system: DialogCellDescriptor(
                kind: .system,
                reuseIdentifier: NSUserInterfaceItemIdentifier("SystemMessageCollectionItem"),
                itemClass: SystemMessageCollectionItem.self
            ),
        ]
    )
}

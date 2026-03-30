import AppKit
import Foundation

@MainActor
final class DialogHistoryViewController: NSViewController {
    private enum Section {
        case main
    }

    private let config: DialogHistoryConfig
    private let cellFactory: DialogCellFactoryProtocol

    private let scrollView = NSScrollView()
    private var collectionView = NSCollectionView()
    private var dataSource: NSCollectionViewDiffableDataSource<Section, UUID>?

    private var orderedIDs: [UUID] = []
    private var stateByID: [UUID: DialogHistoryItemViewState] = [:]
    private var measuredLayoutWidth: CGFloat = 0

    init(
        config: DialogHistoryConfig = .default,
        cellFactory: DialogCellFactoryProtocol? = nil
    ) {
        self.config = config
        self.cellFactory = cellFactory ?? DialogCellFactory(config: config)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCollectionView()
        configureDataSource()
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        let width = max(
            260,
            scrollView.contentView.bounds.width - config.contentInsets.left - config.contentInsets.right
        )
        guard abs(width - measuredLayoutWidth) > 0.5 else { return }

        measuredLayoutWidth = width
        collectionView.collectionViewLayout?.invalidateLayout()
        collectionView.reloadData()
    }

    func apply(items: [DialogHistoryItemViewState]) {
        orderedIDs = items.map(\.id)
        stateByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        var snapshot = NSDiffableDataSourceSnapshot<Section, UUID>()
        snapshot.appendSections([.main])
        snapshot.appendItems(orderedIDs, toSection: .main)
        dataSource?.apply(snapshot, animatingDifferences: config.animateChanges)
        scrollToBottomIfNeeded()
    }

    func apply(patches: [DialogHistoryPatch]) {
        guard !patches.isEmpty else { return }

        var reloadIDs: [UUID] = []

        for patch in patches {
            stateByID[patch.id] = patch.state

            guard let index = orderedIDs.firstIndex(of: patch.id) else {
                continue
            }

            let indexPath = IndexPath(item: index, section: 0)
            if let visible = collectionView.item(at: indexPath) as? DialogCollectionCellProtocol {
                visible.updateVisibleState(patch.state)
            } else {
                reloadIDs.append(patch.id)
            }
        }

        guard !reloadIDs.isEmpty else {
            scrollToBottomIfNeeded()
            return
        }

        var snapshot = dataSource?.snapshot() ?? NSDiffableDataSourceSnapshot<Section, UUID>()
        snapshot.reloadItems(reloadIDs)
        dataSource?.apply(snapshot, animatingDifferences: false)
        scrollToBottomIfNeeded()
    }

    private func setupCollectionView() {
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let layout = NSCollectionViewFlowLayout()
        layout.sectionInset = config.contentInsets
        layout.minimumLineSpacing = config.lineSpacing
        layout.minimumInteritemSpacing = config.interitemSpacing
        layout.estimatedItemSize = .zero

        collectionView = NSCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = false
        collectionView.delegate = self

        cellFactory.registerCells(in: collectionView)

        scrollView.documentView = collectionView
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureDataSource() {
        dataSource = NSCollectionViewDiffableDataSource<Section, UUID>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, itemID in
            guard
                let self,
                let state = self.stateByID[itemID]
            else {
                return NSCollectionViewItem()
            }

            return self.cellFactory.makeItem(in: collectionView, at: indexPath, state: state)
        }
    }

    private func scrollToBottomIfNeeded() {
        guard !orderedIDs.isEmpty else { return }
        let lastIndex = IndexPath(item: orderedIDs.count - 1, section: 0)
        collectionView.scrollToItems(at: [lastIndex], scrollPosition: .bottom)
    }

    private func heightForItem(_ item: DialogHistoryItemViewState, width: CGFloat) -> CGFloat {
        let availableWidth = max(220, width - 20)
        let contentWidth = availableWidth - 20

        if item.kind == .assistant {
            let sections = parseAssistantDisplaySections(item.text)
            let answerHeight = textHeight(
                sections.answer,
                width: contentWidth,
                font: .systemFont(ofSize: 13)
            )

            var contentHeight = answerHeight
            if !sections.evidences.isEmpty {
                contentHeight += 8
                let evidenceSpacing = CGFloat(max(0, sections.evidences.count - 1)) * 8
                let evidenceHeight = sections.evidences.reduce(CGFloat(0)) { partial, evidence in
                    partial + evidenceCardHeight(evidence, width: contentWidth)
                }
                contentHeight += evidenceHeight + evidenceSpacing
            }
            return max(44, ceil(contentHeight) + 34)
        }

        let textRect = (item.text as NSString).boundingRect(
            with: NSSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: 13)],
            context: nil
        )
        return max(44, ceil(textRect.height) + 34)
    }

    private func parseAssistantDisplaySections(_ text: String) -> AssistantDisplaySections {
        let paragraphs = text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let answer = paragraphs.first else {
            return AssistantDisplaySections(answer: text, evidences: [])
        }

        let evidences = paragraphs.dropFirst().compactMap { paragraph -> AssistantEvidenceDisplay? in
            let lines = paragraph
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard lines.count >= 2 else { return nil }
            return AssistantEvidenceDisplay(source: lines[0], quote: lines.dropFirst().joined(separator: "\n"))
        }
        return AssistantDisplaySections(answer: answer, evidences: evidences)
    }

    private func evidenceCardHeight(_ evidence: AssistantEvidenceDisplay, width: CGFloat) -> CGFloat {
        let contentWidth = max(60, width - 16)
        let sourceWidth = max(44, contentWidth - 12)
        let quoteWidth = max(44, contentWidth - 12)
        let sourceHeight = textHeight(evidence.source, width: sourceWidth, font: .systemFont(ofSize: 12, weight: .semibold))
        let quoteHeight = textHeight(evidence.quote, width: quoteWidth, font: .systemFont(ofSize: 12))
        return 8 + (sourceHeight + 12) + 4 + (quoteHeight + 12) + 8
    }

    private func textHeight(_ text: String, width: CGFloat, font: NSFont) -> CGFloat {
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return ceil(rect.height)
    }
}

private struct AssistantDisplaySections {
    let answer: String
    let evidences: [AssistantEvidenceDisplay]
}

private struct AssistantEvidenceDisplay {
    let source: String
    let quote: String
}

extension DialogHistoryViewController: NSCollectionViewDelegateFlowLayout {
    func collectionView(
        _ collectionView: NSCollectionView,
        layout collectionViewLayout: NSCollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> NSSize {
        guard indexPath.item < orderedIDs.count else {
            return NSSize(width: collectionView.bounds.width, height: 44)
        }

        let id = orderedIDs[indexPath.item]
        let state = stateByID[id]
        let width = measuredLayoutWidth > 0
            ? measuredLayoutWidth
            : max(260, collectionView.bounds.width - config.contentInsets.left - config.contentInsets.right)
        let height = heightForItem(state ?? DialogHistoryItemViewState(kind: .system, text: "", status: .sent), width: width)
        return NSSize(width: width, height: height)
    }
}

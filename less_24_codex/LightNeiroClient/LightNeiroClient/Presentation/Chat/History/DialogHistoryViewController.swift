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
        let textRect = (item.text as NSString).boundingRect(
            with: NSSize(width: availableWidth - 20, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: 13)],
            context: nil
        )
        return max(44, ceil(textRect.height) + 34)
    }
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

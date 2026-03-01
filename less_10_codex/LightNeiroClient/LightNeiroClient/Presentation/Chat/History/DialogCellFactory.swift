import AppKit
import Foundation

protocol DialogCellFactoryProtocol {
    func registerCells(in collectionView: NSCollectionView)
    func makeItem(
        in collectionView: NSCollectionView,
        at indexPath: IndexPath,
        state: DialogHistoryItemViewState
    ) -> NSCollectionViewItem
}

final class DialogCellFactory: DialogCellFactoryProtocol {
    private let config: DialogHistoryConfig

    init(config: DialogHistoryConfig) {
        self.config = config
    }

    func registerCells(in collectionView: NSCollectionView) {
        for descriptor in config.cellDescriptors.values {
            collectionView.register(descriptor.itemClass, forItemWithIdentifier: descriptor.reuseIdentifier)
        }
    }

    func makeItem(
        in collectionView: NSCollectionView,
        at indexPath: IndexPath,
        state: DialogHistoryItemViewState
    ) -> NSCollectionViewItem {
        guard let descriptor = config.cellDescriptors[state.kind] else {
            return NSCollectionViewItem()
        }

        let item = collectionView.makeItem(withIdentifier: descriptor.reuseIdentifier, for: indexPath)
        (item as? DialogCollectionCellProtocol)?.apply(state)
        return item
    }
}

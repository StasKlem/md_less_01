import Cocoa

final class RightPaneSplitViewController: NSSplitViewController {
    init(settingsViewController: NSViewController, sessionInfoViewController: NSViewController) {
        super.init(nibName: nil, bundle: nil)

        let top = NSSplitViewItem(viewController: settingsViewController)
        let bottom = NSSplitViewItem(viewController: sessionInfoViewController)

        top.minimumThickness = 220
        bottom.minimumThickness = 180

        addSplitViewItem(top)
        addSplitViewItem(bottom)
        splitView.isVertical = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

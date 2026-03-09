import Cocoa

final class MainSplitViewController: NSSplitViewController {
    private let viewModel: MainViewModel

    init(viewModel: MainViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)

        let chatVC = ChatSidebarViewController(viewModel: viewModel.chatViewModel)
        let settingsVC = SettingsViewController(viewModel: viewModel.settingsViewModel)
        let invariantsVC = InvariantsSettingsViewController(viewModel: viewModel.settingsViewModel)
        let sessionInfoVC = SessionInfoViewController(viewModel: viewModel.sessionInfoViewModel)
        let rightVC = RightPaneSplitViewController(
            settingsViewController: settingsVC,
            invariantsViewController: invariantsVC,
            sessionInfoViewController: sessionInfoVC
        )

        let leftItem = NSSplitViewItem(sidebarWithViewController: chatVC)
        leftItem.minimumThickness = 420
        leftItem.collapseBehavior = .useConstraints
        
        let rightItem = NSSplitViewItem(viewController: rightVC)
        rightItem.collapseBehavior = .useConstraints
        rightItem.maximumThickness = 420


        addSplitViewItem(leftItem)
        addSplitViewItem(rightItem)

        splitView.isVertical = true
        splitView.setPosition(560, ofDividerAt: 0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

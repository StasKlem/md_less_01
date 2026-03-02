import Combine
import Foundation

/// Корневой coordinator ViewModel:
/// связывает чат, настройки и панель метрик в единый поток событий.
final class MainViewModel {
    let chatViewModel: ChatViewModel
    let settingsViewModel: SettingsViewModel
    let sessionInfoViewModel: SessionInfoViewModel

    private var cancellables = Set<AnyCancellable>()

    /// Создаёт MainViewModel и настраивает подписки между дочерними ViewModel.
    init(
        chatViewModel: ChatViewModel,
        settingsViewModel: SettingsViewModel,
        sessionInfoViewModel: SessionInfoViewModel
    ) {
        self.chatViewModel = chatViewModel
        self.settingsViewModel = settingsViewModel
        self.sessionInfoViewModel = sessionInfoViewModel

        chatViewModel.onDidSendMessage = { [weak self] in
            self?.sessionInfoViewModel.refresh()
        }

        chatViewModel.onActiveBranchChanged = { [weak self] branchID in
            // Единая точка синхронизации branch-switch для правой панели:
            // настройки и метрики всегда должны смотреть на ту же ветку, что и чат.
            self?.settingsViewModel.switchActiveBranch(to: branchID)
            self?.sessionInfoViewModel.switchActiveBranch(to: branchID)
            self?.sessionInfoViewModel.refresh()
        }

        settingsViewModel.onSettingsChanged = { [weak self] settings in
            self?.chatViewModel.apply(settings: settings)
            self?.sessionInfoViewModel.refresh()
        }
    }
}

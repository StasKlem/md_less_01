import Combine
import Foundation

final class MainViewModel {
    let chatViewModel: ChatViewModel
    let settingsViewModel: SettingsViewModel
    let sessionInfoViewModel: SessionInfoViewModel

    private var cancellables = Set<AnyCancellable>()

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

        settingsViewModel.onSettingsChanged = { [weak self] settings in
            self?.chatViewModel.apply(settings: settings)
            self?.sessionInfoViewModel.refresh()
        }
    }
}

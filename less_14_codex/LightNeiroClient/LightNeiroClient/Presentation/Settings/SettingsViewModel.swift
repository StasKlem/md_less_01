import Combine
import Foundation

/// ViewModel панели настроек модели, стратегии контекста и API-ключа.
final class SettingsViewModel {
    @Published private(set) var settings: LLMSettings = .default
    @Published private(set) var apiKey: String = ""
    @Published private(set) var apiKeyStatus: String = ""
    @Published private(set) var selectedPromptProfile: UserPromptProfile = .auto
    @Published private(set) var promptProfileText: String = ""
    @Published private(set) var promptProfileStatus: String = ""
    @Published private(set) var doneTransitionMode: DoneTransitionMode = .manualCommand
    @Published private(set) var confirmCommand: String = AgentFlowSettings.default.confirmCommand

    var onSettingsChanged: ((LLMSettings) -> Void)?

    private let sessionID: UUID
    private var activeBranchID: UUID
    private let fetchSettingsUseCase: FetchSettingsUseCaseProtocol
    private let applySettingsUseCase: ApplySettingsUseCaseProtocol
    private let fetchUserPromptProfilesUseCase: FetchUserPromptProfilesUseCaseProtocol
    private let saveUserPromptProfilesUseCase: SaveUserPromptProfilesUseCaseProtocol
    private let loadAPIKeyUseCase: LoadAPIKeyUseCaseProtocol
    private let saveAPIKeyUseCase: SaveAPIKeyUseCaseProtocol
    private var promptProfiles: UserPromptProfiles = .default

    /// Создаёт ViewModel настроек и загружает данные (ключ + настройки сессии).
    init(
        sessionID: UUID,
        activeBranchID: UUID,
        fetchSettingsUseCase: FetchSettingsUseCaseProtocol,
        applySettingsUseCase: ApplySettingsUseCaseProtocol,
        fetchUserPromptProfilesUseCase: FetchUserPromptProfilesUseCaseProtocol,
        saveUserPromptProfilesUseCase: SaveUserPromptProfilesUseCaseProtocol,
        loadAPIKeyUseCase: LoadAPIKeyUseCaseProtocol,
        saveAPIKeyUseCase: SaveAPIKeyUseCaseProtocol
    ) {
        self.sessionID = sessionID
        self.activeBranchID = activeBranchID
        self.fetchSettingsUseCase = fetchSettingsUseCase
        self.applySettingsUseCase = applySettingsUseCase
        self.fetchUserPromptProfilesUseCase = fetchUserPromptProfilesUseCase
        self.saveUserPromptProfilesUseCase = saveUserPromptProfilesUseCase
        self.loadAPIKeyUseCase = loadAPIKeyUseCase
        self.saveAPIKeyUseCase = saveAPIKeyUseCase

        loadAPIKey()
        loadSettings()
        loadPromptProfiles()
    }

    /// Обновляет выбранную модель LLM.
    func updateModel(_ model: LLMModel) {
        settings.model = model
        persist()
    }

    /// Обновляет стратегию контекста для активной ветки.
    func updateContextStrategy(_ strategy: ContextStrategy) {
        // Важно: стратегия меняется для текущей активной ветки, а не глобально для всех веток.
        settings.setContextStrategy(strategy, for: activeBranchID)
        persist()
    }

    /// Обновляет температуру генерации.
    func updateTemperature(_ value: Double) {
        settings.temperature = value
        persist()
    }

    /// Обновляет размер окна контекста для оконных стратегий.
    func updateWindowSize(_ size: Int) {
        settings.windowSize = size
        persist()
    }

    func updateDoneTransitionMode(_ mode: DoneTransitionMode) {
        settings.agentFlowSettings.doneTransitionMode = mode
        doneTransitionMode = mode
        persist()
    }

    func updateConfirmCommand(_ value: String) {
        settings.agentFlowSettings.confirmCommand = value
        confirmCommand = value
        persist()
    }

    /// Переключает активный пользовательский профиль префикса.
    func selectPromptProfile(_ profile: UserPromptProfile) {
        promptProfiles.selectedProfile = profile
        selectedPromptProfile = profile
        promptProfileText = promptProfiles.text(for: profile)
        persistPromptProfiles()
    }

    /// Обновляет текст для выбранного профиля и сохраняет его в долговременную память.
    func updatePromptProfileText(_ text: String) {
        promptProfiles.setText(text, for: selectedPromptProfile)
        promptProfileText = text
        persistPromptProfiles()
    }

    /// Обновляет черновик API-ключа в состоянии ViewModel.
    func updateAPIKey(_ value: String) {
        apiKey = value
        apiKeyStatus = ""
    }

    /// Сохраняет API-ключ в Keychain или удаляет его, если поле пустое.
    func saveAPIKey() {
        let value = apiKey
        do {
            try saveAPIKeyUseCase.execute(apiKey: value)
            apiKeyStatus = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "API key removed from Keychain."
                : "API key saved to Keychain."
        } catch {
            apiKeyStatus = "Failed to save API key: \(error.localizedDescription)"
        }
    }

    /// Переключает контекст настроек на выбранную активную ветку.
    func switchActiveBranch(to branchID: UUID) {
        activeBranchID = branchID
        // При смене ветки подтягиваем ее стратегию в текущее состояние UI
        // и сразу персистим, чтобы остальные подписчики увидели консистентные настройки.
        settings.setContextStrategy(settings.contextStrategy(for: branchID), for: branchID)
        doneTransitionMode = settings.agentFlowSettings.doneTransitionMode
        confirmCommand = settings.agentFlowSettings.confirmCommand
        persist()
    }

    /// Персистит текущие настройки и рассылает обновление подписчикам.
    private func persist() {
        let next = settings
        Task {
            try? await applySettingsUseCase.execute(sessionID: sessionID, settings: next)
            onSettingsChanged?(next)
        }
    }

    /// Загружает API-ключ из Keychain и обновляет состояние экрана.
    private func loadAPIKey() {
        do {
            apiKey = try loadAPIKeyUseCase.execute() ?? ""
        } catch {
            apiKeyStatus = "Failed to load API key: \(error.localizedDescription)"
        }
    }

    /// Загружает настройки сессии и нормализует их для текущей активной ветки.
    private func loadSettings() {
        Task { [weak self] in
            guard let self else { return }
            do {
                var loaded = try await fetchSettingsUseCase.execute(sessionID: sessionID)
                // Нормализуем состояние после загрузки:
                // выбранная в UI стратегия должна соответствовать активной ветке.
                loaded.setContextStrategy(loaded.contextStrategy(for: activeBranchID), for: activeBranchID)
                settings = loaded
                doneTransitionMode = loaded.agentFlowSettings.doneTransitionMode
                confirmCommand = loaded.agentFlowSettings.confirmCommand
                onSettingsChanged?(loaded)
                try await applySettingsUseCase.execute(sessionID: sessionID, settings: loaded)
            } catch {
                apiKeyStatus = "Failed to load settings: \(error.localizedDescription)"
            }
        }
    }

    /// Загружает выбранный профиль и тексты профилей из долговременной памяти.
    private func loadPromptProfiles() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await fetchUserPromptProfilesUseCase.execute(sessionID: sessionID)
                promptProfiles = loaded
                selectedPromptProfile = loaded.selectedProfile
                promptProfileText = loaded.text(for: loaded.selectedProfile)
                promptProfileStatus = ""
            } catch {
                promptProfileStatus = "Failed to load profile settings: \(error.localizedDescription)"
            }
        }
    }

    /// Персистит профили в долговременную память.
    private func persistPromptProfiles() {
        let snapshot = promptProfiles
        Task { [weak self] in
            guard let self else { return }
            do {
                try await saveUserPromptProfilesUseCase.execute(sessionID: sessionID, profiles: snapshot)
                promptProfileStatus = ""
            } catch {
                promptProfileStatus = "Failed to save profile settings: \(error.localizedDescription)"
            }
        }
    }
}

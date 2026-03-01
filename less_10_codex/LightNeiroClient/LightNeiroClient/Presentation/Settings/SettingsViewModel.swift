import Combine
import Foundation

final class SettingsViewModel {
    @Published private(set) var settings: LLMSettings = .default
    @Published private(set) var apiKey: String = ""
    @Published private(set) var apiKeyStatus: String = ""

    var onSettingsChanged: ((LLMSettings) -> Void)?

    private let sessionID: UUID
    private let applySettingsUseCase: ApplySettingsUseCaseProtocol
    private let loadAPIKeyUseCase: LoadAPIKeyUseCaseProtocol
    private let saveAPIKeyUseCase: SaveAPIKeyUseCaseProtocol

    init(
        sessionID: UUID,
        applySettingsUseCase: ApplySettingsUseCaseProtocol,
        loadAPIKeyUseCase: LoadAPIKeyUseCaseProtocol,
        saveAPIKeyUseCase: SaveAPIKeyUseCaseProtocol
    ) {
        self.sessionID = sessionID
        self.applySettingsUseCase = applySettingsUseCase
        self.loadAPIKeyUseCase = loadAPIKeyUseCase
        self.saveAPIKeyUseCase = saveAPIKeyUseCase

        loadAPIKey()
    }

    func updateModel(_ model: LLMModel) {
        settings.model = model
        persist()
    }

    func updateSummarizationMode(_ mode: SummarizationMode) {
        settings.summarizationMode = mode
        persist()
    }

    func updateTemperature(_ value: Double) {
        settings.temperature = value
        persist()
    }

    func updateWindowSize(_ size: Int) {
        settings.windowSize = size
        persist()
    }

    func updateAPIKey(_ value: String) {
        apiKey = value
        apiKeyStatus = ""
    }

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

    private func persist() {
        let next = settings
        Task {
            try? await applySettingsUseCase.execute(sessionID: sessionID, settings: next)
            onSettingsChanged?(next)
        }
    }

    private func loadAPIKey() {
        do {
            apiKey = try loadAPIKeyUseCase.execute() ?? ""
        } catch {
            apiKeyStatus = "Failed to load API key: \(error.localizedDescription)"
        }
    }
}

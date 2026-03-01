import Combine
import Foundation

final class SettingsViewModel {
    @Published private(set) var settings: LLMSettings = .default

    var onSettingsChanged: ((LLMSettings) -> Void)?

    private let sessionID: UUID
    private let applySettingsUseCase: ApplySettingsUseCaseProtocol

    init(sessionID: UUID, applySettingsUseCase: ApplySettingsUseCaseProtocol) {
        self.sessionID = sessionID
        self.applySettingsUseCase = applySettingsUseCase
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

    private func persist() {
        let next = settings
        Task {
            try? await applySettingsUseCase.execute(sessionID: sessionID, settings: next)
            onSettingsChanged?(next)
        }
    }
}

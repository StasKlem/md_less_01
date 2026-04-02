import Combine
import Foundation

final class SettingsViewModel {
    @Published private(set) var settings: LLMSettings = .default
    @Published private(set) var apiKey: String = ""
    @Published private(set) var apiKeyStatus: String = ""
    @Published private(set) var ragEmbeddingsStatus: String = ""
    @Published private(set) var plannerInvariantsText: String = ""
    @Published private(set) var plannerInvariantsStatus: String = ""

    var onSettingsChanged: ((LLMSettings) -> Void)?

    private let fetchSettingsUseCase: FetchSettingsUseCaseProtocol
    private let applySettingsUseCase: ApplySettingsUseCaseProtocol
    private let resetRAGEmbeddingsUseCase: ResetRAGEmbeddingsUseCaseProtocol
    private let loadAPIKeyUseCase: LoadAPIKeyUseCaseProtocol
    private let saveAPIKeyUseCase: SaveAPIKeyUseCaseProtocol

    init(
        fetchSettingsUseCase: FetchSettingsUseCaseProtocol,
        applySettingsUseCase: ApplySettingsUseCaseProtocol,
        resetRAGEmbeddingsUseCase: ResetRAGEmbeddingsUseCaseProtocol,
        loadAPIKeyUseCase: LoadAPIKeyUseCaseProtocol,
        saveAPIKeyUseCase: SaveAPIKeyUseCaseProtocol
    ) {
        self.fetchSettingsUseCase = fetchSettingsUseCase
        self.applySettingsUseCase = applySettingsUseCase
        self.resetRAGEmbeddingsUseCase = resetRAGEmbeddingsUseCase
        self.loadAPIKeyUseCase = loadAPIKeyUseCase
        self.saveAPIKeyUseCase = saveAPIKeyUseCase

        loadAPIKey()
        loadSettings()
    }

    func updateModel(_ model: LLMModel) {
        settings.model = model
        persist()
    }

    func updateBackend(_ backend: LLMBackendKind) {
        settings.backend = backend
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

    func updateMaxTokens(_ value: Int) {
        settings.maxTokens = max(1, value)
        persist()
    }

    func updateRAGEnabled(_ enabled: Bool) {
        settings.isRAGEnabled = enabled
        persist()
    }

    func updateRAGChunkingStrategy(_ strategy: ChunkingStrategyType) {
        settings.ragChunkingStrategy = strategy
        persist()
    }

    func updateRAGPostFilteringEnabled(_ enabled: Bool) {
        settings.isRAGPostFilteringEnabled = enabled
        persist()
    }

    func updateRAGTopKBeforeFiltering(_ value: Int) {
        settings.ragTopKBeforeFiltering = max(1, value)
        persist()
    }

    func updateRAGTopKAfterFiltering(_ value: Int) {
        settings.ragTopKAfterFiltering = max(1, value)
        persist()
    }

    func updateRAGRelevanceThreshold(_ value: Double) {
        settings.ragRelevanceThreshold = min(1.0, max(0.0, value))
        persist()
    }

    func updateMemoryEnabled(_ enabled: Bool) {
        settings.isMemoryEnabled = enabled
        persist()
    }

    func updatePlannerInvariantsText(_ text: String) {
        plannerInvariantsText = text
        plannerInvariantsStatus = ""
    }

    func savePlannerInvariants() {
        let lines = plannerInvariantsText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let normalized = lines.isEmpty ? LLMSettings.default.plannerInvariants : lines
        settings.plannerInvariants = normalized
        plannerInvariantsText = normalized.joined(separator: "\n")
        plannerInvariantsStatus = "Инварианты планировщика сохранены."
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
                ? "API-ключ удален из Keychain."
                : "API-ключ сохранен в Keychain."
        } catch {
            apiKeyStatus = "Не удалось сохранить API-ключ: \(error.localizedDescription)"
        }
    }

    func resetRAGEmbeddings() {
        ragEmbeddingsStatus = "Очистка embeddings..."
        Task { [weak self] in
            guard let self else { return }
            do {
                try await resetRAGEmbeddingsUseCase.execute()
                await MainActor.run {
                    self.ragEmbeddingsStatus = "База embeddings очищена."
                }
            } catch {
                await MainActor.run {
                    self.ragEmbeddingsStatus = "Не удалось очистить embeddings: \(error.localizedDescription)"
                }
            }
        }
    }

    private func persist() {
        let next = settings
        Task {
            try? await applySettingsUseCase.execute(settings: next)
            onSettingsChanged?(next)
        }
    }

    private func loadAPIKey() {
        do {
            apiKey = try loadAPIKeyUseCase.execute() ?? ""
        } catch {
            apiKeyStatus = "Не удалось загрузить API-ключ: \(error.localizedDescription)"
        }
    }

    private func loadSettings() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await fetchSettingsUseCase.execute()
                settings = loaded
                plannerInvariantsText = loaded.plannerInvariants.joined(separator: "\n")
                onSettingsChanged?(loaded)
                try await applySettingsUseCase.execute(settings: loaded)
            } catch {
                apiKeyStatus = "Не удалось загрузить настройки: \(error.localizedDescription)"
            }
        }
    }
}

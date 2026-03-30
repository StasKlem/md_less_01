import Foundation

enum UserDefaultsSettingsRepositoryError: LocalizedError {
    case corruptedData

    var errorDescription: String? {
        switch self {
        case .corruptedData:
            return "Stored settings data is corrupted."
        }
    }
}

/// Persisted settings storage backed by UserDefaults.
struct UserDefaultsSettingsRepository: SettingsRepositoryProtocol {
    private let userDefaults: UserDefaults
    private let storageKey: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "llm.settings.current",
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.encoder = encoder
        self.decoder = decoder
    }

    func fetchSettings() async throws -> LLMSettings {
        guard let data = userDefaults.data(forKey: storageKey) else { return .default }
        return try decode(data)
    }

    func saveSettings(settings: LLMSettings) async throws {
        let data = try encoder.encode(settings)
        userDefaults.set(data, forKey: storageKey)
    }

    private func decode(_ data: Data) throws -> LLMSettings {
        do {
            return try decoder.decode(LLMSettings.self, from: data)
        } catch {
            throw UserDefaultsSettingsRepositoryError.corruptedData
        }
    }
}

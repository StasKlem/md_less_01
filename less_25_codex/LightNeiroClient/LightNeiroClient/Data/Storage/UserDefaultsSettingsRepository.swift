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

    func fetchSettings(sessionID: UUID) async throws -> LLMSettings {
        guard let data = userDefaults.data(forKey: key(for: sessionID)) else {
            // Backward compatibility: if old value was stored without session scoping, reuse it.
            guard let legacyData = userDefaults.data(forKey: storageKey) else {
                return .default
            }
            return try decode(legacyData)
        }
        return try decode(data)
    }

    func saveSettings(sessionID: UUID, settings: LLMSettings) async throws {
        let data = try encoder.encode(settings)
        userDefaults.set(data, forKey: key(for: sessionID))
        // Keep the latest settings under a global key as a fallback for a new session.
        userDefaults.set(data, forKey: storageKey)
    }

    private func key(for sessionID: UUID) -> String {
        "\(storageKey).\(sessionID.uuidString.lowercased())"
    }

    private func decode(_ data: Data) throws -> LLMSettings {
        do {
            return try decoder.decode(LLMSettings.self, from: data)
        } catch {
            throw UserDefaultsSettingsRepositoryError.corruptedData
        }
    }
}

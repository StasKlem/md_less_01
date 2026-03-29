import Foundation
import Security

enum KeychainAPIKeyStoreError: LocalizedError {
    case unexpectedData
    case unhandled(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedData:
            return "Keychain returned unexpected data."
        case let .unhandled(status):
            return "Keychain operation failed with status: \(status)."
        }
    }
}

struct KeychainAPIKeyStore: APIKeyStoreProtocol {
    private let service: String
    private let account: String

    init(
        service: String = "StasKlem.LightNeiroClient",
        account: String = "routerai.api.key"
    ) {
        self.service = service
        self.account = account
    }

    nonisolated func fetchAPIKey() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let key = String(data: data, encoding: .utf8) else {
                throw KeychainAPIKeyStoreError.unexpectedData
            }
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainAPIKeyStoreError.unhandled(status: status)
        }
    }

    nonisolated func saveAPIKey(_ apiKey: String) throws {
        let valueData = Data(apiKey.utf8)
        var query = baseQuery
        query[kSecValueData as String] = valueData

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return
        }
        guard addStatus == errSecDuplicateItem else {
            throw KeychainAPIKeyStoreError.unhandled(status: addStatus)
        }

        let attributes = [kSecValueData as String: valueData]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        guard updateStatus == errSecSuccess else {
            throw KeychainAPIKeyStoreError.unhandled(status: updateStatus)
        }
    }

    nonisolated func deleteAPIKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainAPIKeyStoreError.unhandled(status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

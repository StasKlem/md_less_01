import Foundation

struct PersistedEnvelope<T: Codable>: Codable {
    let schemaVersion: Int
    let payload: T
}

import Foundation

struct UserDefaultsRAGIndexReadinessRepository: RAGIndexReadinessRepositoryProtocol {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func isReady(for strategy: ChunkingStrategyType) -> Bool {
        userDefaults.bool(forKey: readinessKey(for: strategy))
    }

    func markReady(for strategy: ChunkingStrategyType) {
        userDefaults.set(true, forKey: readinessKey(for: strategy))
    }

    func clearAll() {
        for strategy in ChunkingStrategyType.allCases {
            userDefaults.removeObject(forKey: readinessKey(for: strategy))
        }
    }

    private func readinessKey(for strategy: ChunkingStrategyType) -> String {
        "rag.index.ready.\(strategy.rawValue)"
    }
}

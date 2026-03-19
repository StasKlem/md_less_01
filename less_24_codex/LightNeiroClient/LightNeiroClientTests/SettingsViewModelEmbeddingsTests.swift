import XCTest
@testable import LightNeiroClient

@MainActor
final class SettingsViewModelEmbeddingsTests: XCTestCase {
    func testResetRAGEmbeddingsPublishesSuccessStatus() async throws {
        let resetUseCase = ResetRAGEmbeddingsUseCaseSpy()
        let viewModel = makeViewModel(resetUseCase: resetUseCase)

        viewModel.resetRAGEmbeddings()

        let status = await waitForStatus(in: viewModel, equals: "База embeddings очищена.")
        let callCount = await resetUseCase.currentExecuteCallCount()
        XCTAssertEqual(status, "База embeddings очищена.")
        XCTAssertEqual(callCount, 1)
    }

    func testResetRAGEmbeddingsPublishesFailureStatus() async throws {
        let resetUseCase = ResetRAGEmbeddingsUseCaseSpy(error: NSError(domain: "test", code: 42))
        let viewModel = makeViewModel(resetUseCase: resetUseCase)

        viewModel.resetRAGEmbeddings()

        let status = await waitForStatusPrefix(in: viewModel, prefix: "Не удалось очистить embeddings:")
        let callCount = await resetUseCase.currentExecuteCallCount()
        XCTAssertTrue(status.hasPrefix("Не удалось очистить embeddings:"))
        XCTAssertEqual(callCount, 1)
    }

    private func makeViewModel(
        resetUseCase: ResetRAGEmbeddingsUseCaseProtocol
    ) -> SettingsViewModel {
        SettingsViewModel(
            session: ChatSession(
                id: UUID(),
                title: "Тест",
                activeBranchID: UUID(),
                createdAt: Date()
            ),
            fetchSettingsUseCase: FetchSettingsUseCaseStub(),
            applySettingsUseCase: ApplySettingsUseCaseStub(),
            resetRAGEmbeddingsUseCase: resetUseCase,
            loadAPIKeyUseCase: LoadAPIKeyUseCaseStub(),
            saveAPIKeyUseCase: SaveAPIKeyUseCaseStub()
        )
    }

    private func waitForStatus(in viewModel: SettingsViewModel, equals expected: String) async -> String {
        for _ in 0..<50 {
            if viewModel.ragEmbeddingsStatus == expected {
                return viewModel.ragEmbeddingsStatus
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return viewModel.ragEmbeddingsStatus
    }

    private func waitForStatusPrefix(in viewModel: SettingsViewModel, prefix: String) async -> String {
        for _ in 0..<50 {
            if viewModel.ragEmbeddingsStatus.hasPrefix(prefix) {
                return viewModel.ragEmbeddingsStatus
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return viewModel.ragEmbeddingsStatus
    }
}

private actor ResetRAGEmbeddingsUseCaseSpy: ResetRAGEmbeddingsUseCaseProtocol {
    private let error: Error?
    private var executeCallCount = 0

    init(error: Error? = nil) {
        self.error = error
    }

    func execute() async throws {
        executeCallCount += 1
        if let error {
            throw error
        }
    }

    func currentExecuteCallCount() -> Int {
        executeCallCount
    }
}

private struct FetchSettingsUseCaseStub: FetchSettingsUseCaseProtocol {
    func execute(sessionID: UUID) async throws -> LLMSettings {
        _ = sessionID
        return .default
    }
}

private struct ApplySettingsUseCaseStub: ApplySettingsUseCaseProtocol {
    func execute(sessionID: UUID, settings: LLMSettings) async throws {
        _ = sessionID
        _ = settings
    }
}

private struct LoadAPIKeyUseCaseStub: LoadAPIKeyUseCaseProtocol {
    func execute() throws -> String? {
        nil
    }
}

private struct SaveAPIKeyUseCaseStub: SaveAPIKeyUseCaseProtocol {
    func execute(apiKey: String) throws {
        _ = apiKey
    }

    func delete() throws {}
}

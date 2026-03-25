import XCTest
@testable import LightNeiroClient

final class SettingsModelsTests: XCTestCase {
    func testLLMSettingsDecodingFallsBackToDefaultModelForUnknownStoredModel() throws {
        let payload = """
        {
          "backend": "unknown-backend",
          "model": "mistralai/mistral-embed-2312",
          "temperature": 0.5,
          "windowSize": 6,
          "isRAGEnabled": true,
          "isMemoryEnabled": false,
          "plannerInvariants": ["rule-1"]
        }
        """

        let settings = try JSONDecoder().decode(LLMSettings.self, from: Data(payload.utf8))

        XCTAssertEqual(settings.backend, LLMSettings.default.backend)
        XCTAssertEqual(settings.model, LLMSettings.default.model)
        XCTAssertEqual(settings.temperature, 0.5)
        XCTAssertEqual(settings.windowSize, 6)
        XCTAssertTrue(settings.isRAGEnabled)
        XCTAssertEqual(settings.ragChunkingStrategy, LLMSettings.default.ragChunkingStrategy)
        XCTAssertEqual(settings.isRAGPostFilteringEnabled, LLMSettings.default.isRAGPostFilteringEnabled)
        XCTAssertEqual(settings.ragTopKBeforeFiltering, LLMSettings.default.ragTopKBeforeFiltering)
        XCTAssertEqual(settings.ragTopKAfterFiltering, LLMSettings.default.ragTopKAfterFiltering)
        XCTAssertEqual(settings.ragRelevanceThreshold, LLMSettings.default.ragRelevanceThreshold, accuracy: 0.0001)
        XCTAssertFalse(settings.isMemoryEnabled)
        XCTAssertEqual(settings.plannerInvariants, ["rule-1"])
    }

    func testLLMSettingsDefaultUsesRouterAIBackend() {
        XCTAssertEqual(LLMSettings.default.backend, .routerAI)
    }

    func testLLMModelAllCasesIncludesGemmaModel() {
        XCTAssertTrue(LLMModel.allCases.contains(.gemma34B))
        XCTAssertEqual(LLMModel.gemma34B.rawValue, "google/gemma-3-4b")
    }

    func testRAGSettingsDefaultUsesBGEEmbeddingModel() {
        XCTAssertEqual(RAGSettings.default.embeddingModel, "baai/bge-m3")
    }

    func testLLMSettingsDefaultUsesExpectedRAGPostFilteringValues() {
        XCTAssertTrue(LLMSettings.default.isRAGEnabled)
        XCTAssertTrue(LLMSettings.default.isRAGPostFilteringEnabled)
        XCTAssertEqual(LLMSettings.default.ragTopKBeforeFiltering, 8)
        XCTAssertEqual(LLMSettings.default.ragTopKAfterFiltering, 4)
        XCTAssertEqual(LLMSettings.default.ragRelevanceThreshold, 0.70, accuracy: 0.0001)
    }
}

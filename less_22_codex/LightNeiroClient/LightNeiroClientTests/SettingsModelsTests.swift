import XCTest
@testable import LightNeiroClient

final class SettingsModelsTests: XCTestCase {
    func testLLMSettingsDecodingFallsBackToDefaultModelForUnknownStoredModel() throws {
        let payload = """
        {
          "model": "mistralai/mistral-embed-2312",
          "temperature": 0.5,
          "windowSize": 6,
          "isRAGEnabled": true,
          "isMemoryEnabled": false,
          "plannerInvariants": ["rule-1"]
        }
        """

        let settings = try JSONDecoder().decode(LLMSettings.self, from: Data(payload.utf8))

        XCTAssertEqual(settings.model, LLMSettings.default.model)
        XCTAssertEqual(settings.temperature, 0.5)
        XCTAssertEqual(settings.windowSize, 6)
        XCTAssertTrue(settings.isRAGEnabled)
        XCTAssertEqual(settings.ragChunkingStrategy, LLMSettings.default.ragChunkingStrategy)
        XCTAssertFalse(settings.isMemoryEnabled)
        XCTAssertEqual(settings.plannerInvariants, ["rule-1"])
    }

    func testRAGSettingsDefaultUsesMistralEmbeddingModel() {
        XCTAssertEqual(RAGSettings.default.embeddingModel, "mistralai/mistral-embed-2312")
    }
}

import XCTest
@testable import LightNeiroClient

final class VacationPlannerMCPToolsUseCaseTests: XCTestCase {
    func testExecuteReturnsFormattedToolList() async {
        let service = StubMCPToolDiscoveryService(
            result: .success([
                MCPToolSummary(name: "weather_get_forecast", description: "Forecast by city"),
                MCPToolSummary(name: "weather_get_current", description: nil)
            ])
        )
        let useCase = FetchVacationPlannerMCPToolsUseCase(
            toolDiscoveryService: service,
            endpointURL: URL(string: "https://example.com/mcp")!
        )

        let message = await useCase.execute()

        XCTAssertTrue(message.contains("MCP open-weather подключен."))
        XCTAssertTrue(message.contains("- weather_get_current"))
        XCTAssertTrue(message.contains("- weather_get_forecast: Forecast by city"))
    }

    func testExecuteReturnsErrorMessageOnFailure() async {
        let service = StubMCPToolDiscoveryService(result: .failure(StubError.failed))
        let useCase = FetchVacationPlannerMCPToolsUseCase(
            toolDiscoveryService: service,
            endpointURL: URL(string: "https://example.com/mcp")!
        )

        let message = await useCase.execute()

        XCTAssertTrue(message.contains("MCP open-weather: не удалось получить tools"))
    }
}

private enum StubError: LocalizedError {
    case failed

    var errorDescription: String? { "request failed" }
}

private struct StubMCPToolDiscoveryService: MCPToolDiscoveryServiceProtocol {
    let result: Result<[MCPToolSummary], Error>

    func fetchTools(serverURL: URL) async throws -> [MCPToolSummary] {
        try result.get()
    }
}

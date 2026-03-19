import Foundation
import MCP
import Testing
@testable import OpenWeatherMCPServer

struct OpenWeatherToolServiceTests {
    @Test
    func currentWeatherToolReturnsFormattedResponse() async {
        let service = OpenWeatherToolService(
            currentUseCase: StubCurrentWeatherUseCase(),
            forecastUseCase: StubForecastUseCase()
        )

        let result = await service.callTool(
            name: OpenWeatherToolCatalog.currentToolName,
            arguments: [
                "city": "London",
                "units": "metric"
            ]
        )

        #expect(result.isError == false)
        #expect(extractText(result).contains("Current weather for London, GB:"))
        #expect(extractText(result).contains("Temperature: 18.2°C"))
    }

    @Test
    func forecastToolValidatesCountRange() async {
        let service = OpenWeatherToolService(
            currentUseCase: StubCurrentWeatherUseCase(),
            forecastUseCase: StubForecastUseCase()
        )

        let result = await service.callTool(
            name: OpenWeatherToolCatalog.forecastToolName,
            arguments: [
                "city": "Berlin",
                "count": 45
            ]
        )

        #expect(result.isError == true)
        #expect(extractText(result).contains("count"))
        #expect(extractText(result).contains("1...40"))
    }

    @Test
    func unknownToolReturnsError() async {
        let service = OpenWeatherToolService(
            currentUseCase: StubCurrentWeatherUseCase(),
            forecastUseCase: StubForecastUseCase()
        )

        let result = await service.callTool(name: "unknown_tool", arguments: nil)

        #expect(result.isError == true)
        #expect(extractText(result).contains("Unknown tool"))
    }
}

private struct StubCurrentWeatherUseCase: GetCurrentWeatherUseCaseProtocol {
    func execute(city: String, units: TemperatureUnit, lang: String?) async throws -> CurrentWeather {
        CurrentWeather(
            city: city,
            countryCode: "GB",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            temperature: 18.2,
            feelsLike: 17.7,
            humidity: 75,
            windSpeed: 4.8,
            condition: "Clouds",
            description: "broken clouds"
        )
    }
}

private struct StubForecastUseCase: GetForecastUseCaseProtocol {
    func execute(city: String, units: TemperatureUnit, lang: String?, count: Int?) async throws -> ForecastWeather {
        ForecastWeather(
            city: city,
            countryCode: "DE",
            items: [
                ForecastItem(
                    timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                    temperature: 10.1,
                    temperatureMin: 8.0,
                    temperatureMax: 11.4,
                    humidity: 70,
                    description: "light rain"
                )
            ]
        )
    }
}

private func extractText(_ result: CallTool.Result) -> String {
    result.content.compactMap {
        guard case .text(let text) = $0 else { return nil }
        return text
    }.joined(separator: "\n")
}

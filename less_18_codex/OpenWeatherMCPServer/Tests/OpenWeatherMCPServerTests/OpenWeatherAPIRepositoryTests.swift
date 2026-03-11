import Foundation
import Testing
@testable import OpenWeatherMCPServer

struct OpenWeatherAPIRepositoryTests {
    @Test
    func currentWeatherBuildsCorrectURLAndMapsResponse() async throws {
        let client = SpyHTTPClient(
            data: """
            {
              "name": "London",
              "dt": 1700000000,
              "main": { "temp": 15.5, "feels_like": 14.2, "humidity": 81 },
              "wind": { "speed": 3.4 },
              "weather": [{ "main": "Clouds", "description": "few clouds" }],
              "sys": { "country": "GB" }
            }
            """
        )
        let repository = OpenWeatherAPIRepository(
            apiKey: "test-key",
            baseURL: URL(string: "https://api.openweathermap.org")!,
            httpClient: client
        )

        let weather = try await repository.currentWeather(city: "London", units: .metric, lang: "en")

        #expect(weather.city == "London")
        #expect(weather.temperature == 15.5)
        let url = try #require(await client.lastURL)
        #expect(url.path == "/data/2.5/weather")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        #expect(queryItems.contains(.init(name: "q", value: "London")))
        #expect(queryItems.contains(.init(name: "units", value: "metric")))
        #expect(queryItems.contains(.init(name: "appid", value: "test-key")))
        #expect(queryItems.contains(.init(name: "lang", value: "en")))
    }

    @Test
    func forecastIncludesCountQuery() async throws {
        let client = SpyHTTPClient(
            data: """
            {
              "city": { "name": "Berlin", "country": "DE" },
              "list": [
                {
                  "dt": 1700003600,
                  "main": { "temp": 9.2, "temp_min": 8.9, "temp_max": 9.8, "humidity": 77 },
                  "weather": [{ "description": "light rain" }]
                }
              ]
            }
            """
        )
        let repository = OpenWeatherAPIRepository(
            apiKey: "test-key",
            baseURL: URL(string: "https://api.openweathermap.org")!,
            httpClient: client
        )

        let forecast = try await repository.forecast(city: "Berlin", units: .metric, lang: nil, count: 8)

        #expect(forecast.city == "Berlin")
        #expect(forecast.items.count == 1)
        let url = try #require(await client.lastURL)
        #expect(url.path == "/data/2.5/forecast")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        #expect(queryItems.contains(.init(name: "cnt", value: "8")))
    }
}

private actor SpyHTTPClient: HTTPClient {
    private(set) var lastURL: URL?
    private let data: Data

    init(data: String) {
        self.data = Data(data.utf8)
    }

    func get(url: URL) async throws -> Data {
        lastURL = url
        return data
    }
}

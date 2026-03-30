import Foundation

struct OpenWeatherAPIRepository: OpenWeatherRepository {
    private let apiKey: String?
    private let baseURL: URL
    private let httpClient: HTTPClient
    private let decoder: JSONDecoder

    init(
        apiKey: String?,
        baseURL: URL,
        httpClient: HTTPClient,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.httpClient = httpClient
        self.decoder = decoder
    }

    func currentWeather(city: String, units: TemperatureUnit, lang: String?) async throws -> CurrentWeather {
        let url = try makeURL(
            path: "/data/2.5/weather",
            queryItems: try baseQueryItems(city: city, units: units, lang: lang, count: nil)
        )
        do {
            let data = try await httpClient.get(url: url)
            let dto = try decoder.decode(CurrentWeatherResponseDTO.self, from: data)
            return dto.toDomain()
        } catch let error as OpenWeatherToolError {
            throw error
        } catch {
            throw OpenWeatherToolError.decodingFailure(error.localizedDescription)
        }
    }

    func forecast(city: String, units: TemperatureUnit, lang: String?, count: Int?) async throws -> ForecastWeather {
        let url = try makeURL(
            path: "/data/2.5/forecast",
            queryItems: try baseQueryItems(city: city, units: units, lang: lang, count: count)
        )
        do {
            let data = try await httpClient.get(url: url)
            let dto = try decoder.decode(ForecastResponseDTO.self, from: data)
            return dto.toDomain()
        } catch let error as OpenWeatherToolError {
            throw error
        } catch {
            throw OpenWeatherToolError.decodingFailure(error.localizedDescription)
        }
    }

    private func baseQueryItems(
        city: String,
        units: TemperatureUnit,
        lang: String?,
        count: Int?
    ) throws -> [URLQueryItem] {
        guard let apiKey, !apiKey.isEmpty else {
            throw OpenWeatherToolError.missingAPIKey
        }
        var items: [URLQueryItem] = [
            .init(name: "q", value: city),
            .init(name: "appid", value: apiKey),
            .init(name: "units", value: units.rawValue)
        ]
        if let lang {
            items.append(.init(name: "lang", value: lang))
        }
        if let count {
            items.append(.init(name: "cnt", value: String(count)))
        }
        return items
    }

    private func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw OpenWeatherToolError.upstreamFailure("Could not build request URL.")
        }
        return url
    }
}

private struct CurrentWeatherResponseDTO: Decodable {
    struct MainDTO: Decodable {
        let temp: Double
        let feelsLike: Double
        let humidity: Int

        private enum CodingKeys: String, CodingKey {
            case temp
            case feelsLike = "feels_like"
            case humidity
        }
    }

    struct WindDTO: Decodable {
        let speed: Double
    }

    struct WeatherDTO: Decodable {
        let main: String
        let description: String
    }

    struct SysDTO: Decodable {
        let country: String?
    }

    let name: String
    let dt: Int
    let main: MainDTO
    let wind: WindDTO
    let weather: [WeatherDTO]
    let sys: SysDTO?

    func toDomain() -> CurrentWeather {
        let firstWeather = weather.first
        return CurrentWeather(
            city: name,
            countryCode: sys?.country,
            timestamp: Date(timeIntervalSince1970: TimeInterval(dt)),
            temperature: main.temp,
            feelsLike: main.feelsLike,
            humidity: main.humidity,
            windSpeed: wind.speed,
            condition: firstWeather?.main ?? "Unknown",
            description: firstWeather?.description ?? "No description"
        )
    }
}

private struct ForecastResponseDTO: Decodable {
    struct CityDTO: Decodable {
        let name: String
        let country: String?
    }

    struct MainDTO: Decodable {
        let temp: Double
        let tempMin: Double
        let tempMax: Double
        let humidity: Int

        private enum CodingKeys: String, CodingKey {
            case temp
            case tempMin = "temp_min"
            case tempMax = "temp_max"
            case humidity
        }
    }

    struct WeatherDTO: Decodable {
        let description: String
    }

    struct ItemDTO: Decodable {
        let dt: Int
        let main: MainDTO
        let weather: [WeatherDTO]
    }

    let city: CityDTO
    let list: [ItemDTO]

    func toDomain() -> ForecastWeather {
        ForecastWeather(
            city: city.name,
            countryCode: city.country,
            items: list.map { item in
                ForecastItem(
                    timestamp: Date(timeIntervalSince1970: TimeInterval(item.dt)),
                    temperature: item.main.temp,
                    temperatureMin: item.main.tempMin,
                    temperatureMax: item.main.tempMax,
                    humidity: item.main.humidity,
                    description: item.weather.first?.description ?? "No description"
                )
            }
        )
    }
}

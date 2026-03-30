import Foundation

enum TemperatureUnit: String, Sendable {
    case standard
    case metric
    case imperial

    var symbol: String {
        switch self {
        case .standard:
            return "K"
        case .metric:
            return "C"
        case .imperial:
            return "F"
        }
    }

    static func parse(_ raw: String?) throws -> TemperatureUnit {
        guard let raw else { return .metric }
        guard let unit = TemperatureUnit(rawValue: raw.lowercased()) else {
            throw OpenWeatherToolError.invalidArguments(
                "Unsupported units '\(raw)'. Expected one of: standard, metric, imperial."
            )
        }
        return unit
    }
}

struct CurrentWeather: Sendable {
    let city: String
    let countryCode: String?
    let timestamp: Date
    let temperature: Double
    let feelsLike: Double
    let humidity: Int
    let windSpeed: Double
    let condition: String
    let description: String
}

struct ForecastItem: Sendable {
    let timestamp: Date
    let temperature: Double
    let temperatureMin: Double
    let temperatureMax: Double
    let humidity: Int
    let description: String
}

struct ForecastWeather: Sendable {
    let city: String
    let countryCode: String?
    let items: [ForecastItem]
}

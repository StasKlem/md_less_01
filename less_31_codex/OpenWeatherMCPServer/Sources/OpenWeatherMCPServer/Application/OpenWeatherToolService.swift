import Foundation
import MCP

struct OpenWeatherToolService: Sendable {
    private let currentUseCase: GetCurrentWeatherUseCaseProtocol
    private let forecastUseCase: GetForecastUseCaseProtocol
    private let defaultLanguage: String?

    init(
        currentUseCase: GetCurrentWeatherUseCaseProtocol,
        forecastUseCase: GetForecastUseCaseProtocol,
        defaultLanguage: String? = nil
    ) {
        self.currentUseCase = currentUseCase
        self.forecastUseCase = forecastUseCase
        self.defaultLanguage = defaultLanguage
    }

    func callTool(name: String, arguments: [String: Value]?) async -> CallTool.Result {
        do {
            switch name {
            case OpenWeatherToolCatalog.currentToolName:
                return try await handleCurrent(arguments: arguments)
            case OpenWeatherToolCatalog.forecastToolName:
                return try await handleForecast(arguments: arguments)
            default:
                return Self.errorResult("Unknown tool: \(name)")
            }
        } catch {
            return Self.errorResult(error.localizedDescription)
        }
    }

    private func handleCurrent(arguments: [String: Value]?) async throws -> CallTool.Result {
        let parsed = try CurrentWeatherArguments.parse(arguments: arguments, defaultLanguage: defaultLanguage)
        let weather = try await currentUseCase.execute(
            city: parsed.city,
            units: parsed.units,
            lang: parsed.lang
        )
        return .init(content: [.text(CurrentWeatherFormatter.format(weather, units: parsed.units))], isError: false)
    }

    private func handleForecast(arguments: [String: Value]?) async throws -> CallTool.Result {
        let parsed = try ForecastArguments.parse(arguments: arguments, defaultLanguage: defaultLanguage)
        let forecast = try await forecastUseCase.execute(
            city: parsed.city,
            units: parsed.units,
            lang: parsed.lang,
            count: parsed.count
        )
        return .init(content: [.text(ForecastFormatter.format(forecast, units: parsed.units))], isError: false)
    }

    private static func errorResult(_ message: String) -> CallTool.Result {
        .init(content: [.text(message)], isError: true)
    }
}

private struct CurrentWeatherArguments {
    let city: String
    let units: TemperatureUnit
    let lang: String?

    static func parse(arguments: [String: Value]?, defaultLanguage: String?) throws -> CurrentWeatherArguments {
        let city = try RequiredArguments.city(from: arguments)
        let units = try TemperatureUnit.parse(arguments?["units"]?.stringValue)
        let lang = arguments?["lang"]?.stringValue ?? defaultLanguage
        return .init(city: city, units: units, lang: lang)
    }
}

private struct ForecastArguments {
    let city: String
    let units: TemperatureUnit
    let lang: String?
    let count: Int?

    static func parse(arguments: [String: Value]?, defaultLanguage: String?) throws -> ForecastArguments {
        let city = try RequiredArguments.city(from: arguments)
        let units = try TemperatureUnit.parse(arguments?["units"]?.stringValue)
        let lang = arguments?["lang"]?.stringValue ?? defaultLanguage
        let count = try parseCount(arguments?["count"])
        return .init(city: city, units: units, lang: lang, count: count)
    }

    private static func parseCount(_ value: Value?) throws -> Int? {
        guard let value else { return nil }
        guard let count = value.intValue else {
            throw OpenWeatherToolError.invalidArguments("Argument 'count' must be an integer.")
        }
        guard (1...40).contains(count) else {
            throw OpenWeatherToolError.invalidArguments("Argument 'count' must be in range 1...40.")
        }
        return count
    }
}

private enum RequiredArguments {
    static func city(from arguments: [String: Value]?) throws -> String {
        guard let city = arguments?["city"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !city.isEmpty
        else {
            throw OpenWeatherToolError.invalidArguments("Argument 'city' is required.")
        }
        return city
    }
}

private enum CurrentWeatherFormatter {
    static func format(_ weather: CurrentWeather, units: TemperatureUnit) -> String {
        let country = weather.countryCode.map { ", \($0)" } ?? ""
        return """
        Current weather for \(weather.city)\(country):
        - Conditions: \(weather.description) (\(weather.condition))
        - Temperature: \(rounded(weather.temperature))°\(units.symbol)
        - Feels like: \(rounded(weather.feelsLike))°\(units.symbol)
        - Humidity: \(weather.humidity)%
        - Wind speed: \(rounded(weather.windSpeed))
        """
    }
}

private enum ForecastFormatter {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static func format(_ forecast: ForecastWeather, units: TemperatureUnit) -> String {
        let country = forecast.countryCode.map { ", \($0)" } ?? ""
        var lines: [String] = ["Forecast for \(forecast.city)\(country):"]
        if forecast.items.isEmpty {
            lines.append("- No forecast items returned.")
            return lines.joined(separator: "\n")
        }

        for item in forecast.items {
            let dateText = dateFormatter.string(from: item.timestamp)
            lines.append(
                "- \(dateText) UTC: \(item.description), \(rounded(item.temperature))°\(units.symbol) "
                    + "(min \(rounded(item.temperatureMin))°\(units.symbol), "
                    + "max \(rounded(item.temperatureMax))°\(units.symbol)), humidity \(item.humidity)%"
            )
        }
        return lines.joined(separator: "\n")
    }
}

private func rounded(_ value: Double) -> String {
    String(format: "%.1f", value)
}

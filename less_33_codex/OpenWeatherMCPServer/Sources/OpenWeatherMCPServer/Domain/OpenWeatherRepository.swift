import Foundation

protocol OpenWeatherRepository: Sendable {
    func currentWeather(city: String, units: TemperatureUnit, lang: String?) async throws -> CurrentWeather
    func forecast(city: String, units: TemperatureUnit, lang: String?, count: Int?) async throws -> ForecastWeather
}

import Foundation

protocol GetCurrentWeatherUseCaseProtocol: Sendable {
    func execute(city: String, units: TemperatureUnit, lang: String?) async throws -> CurrentWeather
}

protocol GetForecastUseCaseProtocol: Sendable {
    func execute(city: String, units: TemperatureUnit, lang: String?, count: Int?) async throws -> ForecastWeather
}

struct GetCurrentWeatherUseCase: GetCurrentWeatherUseCaseProtocol {
    private let repository: OpenWeatherRepository

    init(repository: OpenWeatherRepository) {
        self.repository = repository
    }

    func execute(city: String, units: TemperatureUnit, lang: String?) async throws -> CurrentWeather {
        try await repository.currentWeather(city: city, units: units, lang: lang)
    }
}

struct GetForecastUseCase: GetForecastUseCaseProtocol {
    private let repository: OpenWeatherRepository

    init(repository: OpenWeatherRepository) {
        self.repository = repository
    }

    func execute(city: String, units: TemperatureUnit, lang: String?, count: Int?) async throws -> ForecastWeather {
        try await repository.forecast(city: city, units: units, lang: lang, count: count)
    }
}

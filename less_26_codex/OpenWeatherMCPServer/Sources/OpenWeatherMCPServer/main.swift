import Foundation
import MCP

enum OpenWeatherMCPServerApp {
    static func run() async -> Int32 {
        do {
            let config = try AppConfiguration.fromEnvironment()
            let repository = OpenWeatherAPIRepository(
                apiKey: config.apiKey,
                baseURL: config.baseURL,
                httpClient: URLSessionHTTPClient()
            )
            let service = OpenWeatherToolService(
                currentUseCase: GetCurrentWeatherUseCase(repository: repository),
                forecastUseCase: GetForecastUseCase(repository: repository),
                defaultLanguage: config.defaultLanguage
            )

            let server = Server(
                name: "open-weather",
                version: "1.0.0",
                instructions:
                    "Use weather_get_current for current weather and weather_get_forecast for forecast by city.",
                capabilities: .init(
                    tools: .init(listChanged: false)
                )
            )

            await server.withMethodHandler(ListTools.self) { _ in
                .init(tools: OpenWeatherToolCatalog.tools)
            }

            await server.withMethodHandler(CallTool.self) { params in
                await service.callTool(name: params.name, arguments: params.arguments)
            }

            let transport = StdioTransport()
            try await server.start(transport: transport)
            await server.waitUntilCompleted()
            return 0
        } catch {
            FileHandle.standardError.write(Data("OpenWeatherMCPServer error: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }
}

let exitCode = await OpenWeatherMCPServerApp.run()
Foundation.exit(exitCode)

private struct AppConfiguration {
    let apiKey: String?
    let baseURL: URL
    let defaultLanguage: String?

    static func fromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> AppConfiguration {
        let apiKey = environment["OPENWEATHER_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let baseURL: URL
        if let rawBaseURL = environment["OPENWEATHER_BASE_URL"], !rawBaseURL.isEmpty {
            guard let parsed = URL(string: rawBaseURL) else {
                throw OpenWeatherToolError.invalidArguments(
                    "OPENWEATHER_BASE_URL is not a valid URL."
                )
            }
            baseURL = parsed
        } else {
            guard let parsed = URL(string: "https://api.openweathermap.org") else {
                throw OpenWeatherToolError.upstreamFailure("Could not build default OpenWeatherMap URL.")
            }
            baseURL = parsed
        }

        let defaultLanguage = environment["OPENWEATHER_DEFAULT_LANG"]?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let normalizedDefaultLanguage = defaultLanguage?.isEmpty == true ? nil : defaultLanguage

        return AppConfiguration(
            apiKey: (apiKey?.isEmpty == true) ? nil : apiKey,
            baseURL: baseURL,
            defaultLanguage: normalizedDefaultLanguage
        )
    }
}

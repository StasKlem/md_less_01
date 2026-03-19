import Foundation

enum OpenWeatherToolError: LocalizedError, Sendable {
    case missingAPIKey
    case invalidArguments(String)
    case upstreamFailure(String)
    case decodingFailure(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing OPENWEATHER_API_KEY environment variable."
        case .invalidArguments(let message):
            return message
        case .upstreamFailure(let message):
            return "OpenWeatherMap request failed: \(message)"
        case .decodingFailure(let message):
            return "OpenWeatherMap response parsing failed: \(message)"
        }
    }
}

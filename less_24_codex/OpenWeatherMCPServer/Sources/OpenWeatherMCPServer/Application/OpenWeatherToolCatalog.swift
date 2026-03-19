import MCP

enum OpenWeatherToolCatalog {
    static let currentToolName = "weather_get_current"
    static let forecastToolName = "weather_get_forecast"

    static let tools: [Tool] = [
        Tool(
            name: currentToolName,
            description: "Get current weather by city name.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "city": .object([
                        "type": "string",
                        "description": "City name. Example: London"
                    ]),
                    "units": .object([
                        "type": "string",
                        "description": "Units system: standard, metric, imperial."
                    ]),
                    "lang": .object([
                        "type": "string",
                        "description": "Language code for weather description. Example: en, ru."
                    ])
                ]),
                "required": ["city"],
                "additionalProperties": false
            ]),
            annotations: .init(
                title: "Current Weather",
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: true
            )
        ),
        Tool(
            name: forecastToolName,
            description: "Get weather forecast by city name.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "city": .object([
                        "type": "string",
                        "description": "City name. Example: London"
                    ]),
                    "units": .object([
                        "type": "string",
                        "description": "Units system: standard, metric, imperial."
                    ]),
                    "lang": .object([
                        "type": "string",
                        "description": "Language code for weather description. Example: en, ru."
                    ]),
                    "count": .object([
                        "type": "integer",
                        "description": "Number of forecast items to return (1...40)."
                    ])
                ]),
                "required": ["city"],
                "additionalProperties": false
            ]),
            annotations: .init(
                title: "Weather Forecast",
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: true
            )
        )
    ]
}

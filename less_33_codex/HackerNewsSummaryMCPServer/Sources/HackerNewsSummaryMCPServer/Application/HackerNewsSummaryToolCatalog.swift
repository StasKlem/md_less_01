import MCP

enum HackerNewsSummaryToolCatalog {
    static let summarizeToolName = "hackernews_summarize_stories"

    static let tools: [Tool] = [
        Tool(
            name: summarizeToolName,
            description: "Summarize a list of Hacker News stories provided in the text format returned by hackernews_get_random_story.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "stories": .object([
                        "type": "array",
                        "items": .object([
                            "type": "string",
                            "description": "Single story text block from hackernews_get_random_story output."
                        ]),
                        "minItems": 1
                    ]),
                    "language": .object([
                        "type": "string",
                        "description": "Output language code or natural language name. Example: ru, en, Russian."
                    ])
                ]),
                "required": .array(["stories"]),
                "additionalProperties": false
            ]),
            annotations: .init(
                title: "Summarize Hacker News Stories",
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: false,
                openWorldHint: true
            )
        )
    ]
}

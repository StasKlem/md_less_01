import MCP

enum HackerNewsTranslateToolCatalog {
    static let translateToolName = "hackernews_translate_story"

    static let tools: [Tool] = [
        Tool(
            name: translateToolName,
            description: "Translate one Hacker News story provided in the text format returned by hackernews_get_random_story.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "story": .object([
                        "type": "string",
                        "description": "Story text block from hackernews_get_random_story output."
                    ]),
                    "language": .object([
                        "type": "string",
                        "description": "Output language code or natural language name. Example: ru, en, Russian."
                    ])
                ]),
                "required": .array(["story"]),
                "additionalProperties": false
            ]),
            annotations: .init(
                title: "Translate Hacker News Story",
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: false,
                openWorldHint: true
            )
        )
    ]
}

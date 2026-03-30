import MCP

enum HackerNewsToolCatalog {
    static let randomStoryToolName = "hackernews_get_random_story"

    static let tools: [Tool] = [
        Tool(
            name: randomStoryToolName,
            description: "Get one random top story from Hacker News.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([:]),
                "additionalProperties": false
            ]),
            annotations: .init(
                title: "Random Hacker News Story",
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: false,
                openWorldHint: true
            )
        )
    ]
}

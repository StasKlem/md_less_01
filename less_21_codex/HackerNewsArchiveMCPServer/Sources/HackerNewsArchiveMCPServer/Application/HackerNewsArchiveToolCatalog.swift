import MCP

enum HackerNewsArchiveToolCatalog {
    static let saveJSONToolName = "hackernews_archive_save_json"
    static let listLatestToolName = "hackernews_archive_get_latest_files"

    static let tools: [Tool] = [
        Tool(
            name: saveJSONToolName,
            description: "Save Hacker News JSON payload to a local file.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "json": .object([
                        "type": "string",
                        "description": "Raw JSON payload to store."
                    ])
                ]),
                "required": ["json"],
                "additionalProperties": false
            ]),
            annotations: .init(
                title: "Save Hacker News JSON",
                readOnlyHint: false,
                destructiveHint: false,
                idempotentHint: false,
                openWorldHint: false
            )
        ),
        Tool(
            name: listLatestToolName,
            description: "Return the latest 3 saved Hacker News JSON files.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([:]),
                "additionalProperties": false
            ]),
            annotations: .init(
                title: "List Latest Hacker News Files",
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        )
    ]
}

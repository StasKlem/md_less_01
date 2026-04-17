import MCP

enum ProjectToolCatalog {
    static let currentGitBranchToolName = "project_git_branch"
    static let listProjectFilesToolName = "project_list_files"
    static let uncommittedChangesToolName = "project_uncommitted_changes"
    static let readProjectFileToolName = "project_read_file"
    static let searchProjectFilesToolName = "project_search_files"
    static let writeProjectFileToolName = "project_write_file"

    static let tools: [Tool] = [
        Tool(
            name: currentGitBranchToolName,
            description: "Возвращает текущую git-ветку проекта.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([:]),
                "additionalProperties": false
            ]),
            annotations: .init(
                title: "Current Git Branch",
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        ),
        Tool(
            name: listProjectFilesToolName,
            description: "Возвращает список файлов проекта.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([:]),
                "additionalProperties": false
            ]),
            annotations: .init(
                title: "Project Files",
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        ),
        Tool(
            name: readProjectFileToolName,
            description: "Читает содержимое файла проекта по относительному пути.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "relativePath": .object([
                        "type": "string",
                        "description": "Относительный путь к файлу."
                    ])
                ]),
                "required": .array([.string("relativePath")]),
                "additionalProperties": false
            ]),
            annotations: .init(
                title: "Read Project File",
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        ),
        Tool(
            name: searchProjectFilesToolName,
            description: "Ищет текст по файлам проекта и возвращает совпадения с номерами строк.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "query": .object([
                        "type": "string",
                        "description": "Текст для поиска."
                    ])
                ]),
                "required": .array([.string("query")]),
                "additionalProperties": false
            ]),
            annotations: .init(
                title: "Search Project Files",
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        ),
        Tool(
            name: writeProjectFileToolName,
            description: "Создает или обновляет файл проекта по относительному пути и возвращает diff.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "relativePath": .object([
                        "type": "string",
                        "description": "Относительный путь к файлу."
                    ]),
                    "content": .object([
                        "type": "string",
                        "description": "Новое содержимое файла."
                    ])
                ]),
                "required": .array([.string("relativePath"), .string("content")]),
                "additionalProperties": false
            ]),
            annotations: .init(
                title: "Write Project File",
                readOnlyHint: false,
                destructiveHint: false,
                idempotentHint: false,
                openWorldHint: false
            )
        ),
        Tool(
            name: uncommittedChangesToolName,
            description: "Возвращает список незакоммиченных файлов и unified diff.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([:]),
                "additionalProperties": false
            ]),
            annotations: .init(
                title: "Uncommitted Changes",
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        )
    ]
}

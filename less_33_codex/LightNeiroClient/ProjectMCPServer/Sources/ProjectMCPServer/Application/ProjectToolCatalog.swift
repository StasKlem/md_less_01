import MCP

enum ProjectToolCatalog {
    static let currentGitBranchToolName = "project_git_branch"
    static let listProjectFilesToolName = "project_list_files"
    static let uncommittedChangesToolName = "project_uncommitted_changes"

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

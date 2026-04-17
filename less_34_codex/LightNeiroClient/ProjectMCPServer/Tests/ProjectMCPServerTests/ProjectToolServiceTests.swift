import MCP
import XCTest
@testable import ProjectMCPServer

final class ProjectToolServiceTests: XCTestCase {
    func testCurrentGitBranchToolReturnsBranchName() async {
        let fileSystem = TemporaryWorkspaceFixture()
        defer { fileSystem.cleanup() }

        let repository = MockProjectRepository(
            branch: "feature/project-mcp",
            files: []
        )
        let service = makeService(
            repository: repository,
            workspaceRepository: fileSystem.workspaceRepository
        )

        let result = await service.callTool(
            name: ProjectToolCatalog.currentGitBranchToolName,
            arguments: [:]
        )

        XCTAssertFalse(result.isError ?? true)
        XCTAssertEqual(extractText(from: result.content), "feature/project-mcp")
    }

    func testListProjectFilesToolReturnsFormattedFileList() async {
        let fileSystem = TemporaryWorkspaceFixture()
        defer { fileSystem.cleanup() }

        let repository = MockProjectRepository(
            branch: "main",
            files: [
                ProjectFile(relativePath: "Package.swift"),
                ProjectFile(relativePath: "Sources/ProjectMCPServer/main.swift")
            ]
        )
        let service = makeService(
            repository: repository,
            workspaceRepository: fileSystem.workspaceRepository
        )

        let result = await service.callTool(
            name: ProjectToolCatalog.listProjectFilesToolName,
            arguments: [:]
        )

        XCTAssertFalse(result.isError ?? true)
        let text = extractText(from: result.content)
        XCTAssertTrue(text.contains("Project files (2):"), "Ответ: \(text)")
        XCTAssertTrue(text.contains("Package.swift"), "Ответ: \(text)")
        XCTAssertTrue(text.contains("Sources/ProjectMCPServer/main.swift"), "Ответ: \(text)")
    }

    func testUncommittedChangesToolReturnsJsonPayload() async throws {
        let fileSystem = TemporaryWorkspaceFixture()
        defer { fileSystem.cleanup() }

        let repository = MockProjectRepository(
            branch: "main",
            files: [
                ProjectFile(relativePath: "Package.swift")
            ],
            uncommittedChanges: ProjectUncommittedChanges(
                files: [
                    ProjectFile(relativePath: "Package.swift")
                ],
                diff: "diff --git a/Package.swift b/Package.swift\n--- a/Package.swift\n+++ b/Package.swift"
            )
        )
        let service = makeService(
            repository: repository,
            workspaceRepository: fileSystem.workspaceRepository
        )

        let result = await service.callTool(
            name: ProjectToolCatalog.uncommittedChangesToolName,
            arguments: [:]
        )

        XCTAssertFalse(result.isError ?? true)
        let text = extractText(from: result.content)
        XCTAssertTrue(text.contains("\"files\""), "Ответ: \(text)")
        XCTAssertTrue(text.contains("Package.swift"), "Ответ: \(text)")
        XCTAssertTrue(text.contains("\"diff\""), "Ответ: \(text)")
    }

    func testReadProjectFileToolReturnsFileContent() async {
        let fileSystem = TemporaryWorkspaceFixture()
        defer { fileSystem.cleanup() }

        let repository = MockProjectRepository(branch: "main", files: [])
        let service = makeService(
            repository: repository,
            workspaceRepository: fileSystem.workspaceRepository
        )

        let result = await service.callTool(
            name: ProjectToolCatalog.readProjectFileToolName,
            arguments: ["relativePath": .string("Docs/guide.md")]
        )

        XCTAssertFalse(result.isError ?? true)
        let text = extractText(from: result.content)
        XCTAssertTrue(text.contains("\"relativePath\""), "Ответ: \(text)")
        XCTAssertTrue(text.contains("Docs/guide.md"), "Ответ: \(text)")
        XCTAssertTrue(text.contains("Hello from guide"), "Ответ: \(text)")
    }

    func testSearchProjectFilesToolFindsMatchesAcrossFiles() async {
        let fileSystem = TemporaryWorkspaceFixture()
        defer { fileSystem.cleanup() }

        let repository = MockProjectRepository(
            branch: "main",
            files: [
                ProjectFile(relativePath: "Docs/guide.md"),
                ProjectFile(relativePath: "Sources/App.swift"),
                ProjectFile(relativePath: "README.md")
            ]
        )
        let service = makeService(
            repository: repository,
            workspaceRepository: fileSystem.workspaceRepository
        )

        let result = await service.callTool(
            name: ProjectToolCatalog.searchProjectFilesToolName,
            arguments: ["query": .string("AlphaComponent")]
        )

        XCTAssertFalse(result.isError ?? true)
        let text = extractText(from: result.content)
        XCTAssertTrue(text.contains("\"query\""), "Ответ: \(text)")
        XCTAssertTrue(text.contains("AlphaComponent"), "Ответ: \(text)")
        XCTAssertTrue(text.contains("Docs/guide.md"), "Ответ: \(text)")
        XCTAssertTrue(text.contains("Sources/App.swift"), "Ответ: \(text)")
    }

    func testWriteProjectFileToolCreatesFileAndReturnsDiff() async {
        let fileSystem = TemporaryWorkspaceFixture()
        defer { fileSystem.cleanup() }

        let repository = MockProjectRepository(branch: "main", files: [])
        let service = makeService(
            repository: repository,
            workspaceRepository: fileSystem.workspaceRepository
        )

        let result = await service.callTool(
            name: ProjectToolCatalog.writeProjectFileToolName,
            arguments: [
                "relativePath": .string("Docs/new-note.md"),
                "content": .string("# New note\n\nCreated by test.")
            ]
        )

        XCTAssertFalse(result.isError ?? true)
        let text = extractText(from: result.content)
        XCTAssertTrue(text.contains("\"created\""), "Ответ: \(text)")
        XCTAssertTrue(text.contains("\"changed\""), "Ответ: \(text)")
        XCTAssertTrue(text.contains("Docs/new-note.md"), "Ответ: \(text)")
        XCTAssertTrue(text.contains("New note"), "Ответ: \(text)")

        let writtenFile = fileSystem.root.appendingPathComponent("Docs/new-note.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: writtenFile.path))
        let writtenText = try! String(contentsOf: writtenFile, encoding: .utf8)
        XCTAssertTrue(writtenText.contains("Created by test."))
    }

    private func extractText(from content: [Tool.Content]) -> String {
        content.compactMap { item in
            if case .text(let text) = item {
                return text
            }
            return nil
        }
        .joined(separator: "\n")
    }

    private func makeService(
        repository: MockProjectRepository,
        workspaceRepository: FileSystemProjectWorkspaceRepository
    ) -> ProjectToolService {
        ProjectToolService(
            getCurrentGitBranchUseCase: GetCurrentGitBranchUseCase(repository: repository),
            listProjectFilesUseCase: ListProjectFilesUseCase(repository: repository),
            getUncommittedChangesUseCase: GetUncommittedChangesUseCase(repository: repository),
            readProjectFileUseCase: ReadProjectFileUseCase(repository: workspaceRepository),
            searchProjectFilesUseCase: SearchProjectFilesUseCase(
                projectRepository: repository,
                workspaceRepository: workspaceRepository
            ),
            writeProjectFileUseCase: WriteProjectFileUseCase(repository: workspaceRepository)
        )
    }
}

private struct MockProjectRepository: ProjectRepositoryProtocol {
    let branch: String
    let files: [ProjectFile]
    let uncommittedChangesValue: ProjectUncommittedChanges

    init(
        branch: String,
        files: [ProjectFile],
        uncommittedChanges: ProjectUncommittedChanges = ProjectUncommittedChanges(files: [], diff: "")
    ) {
        self.branch = branch
        self.files = files
        self.uncommittedChangesValue = uncommittedChanges
    }

    func currentGitBranch() throws -> String {
        branch
    }

    func listProjectFiles() throws -> [ProjectFile] {
        files
    }

    func uncommittedChanges() throws -> ProjectUncommittedChanges {
        uncommittedChangesValue
    }
}

private final class TemporaryWorkspaceFixture {
    let root: URL
    let workspaceRepository: FileSystemProjectWorkspaceRepository

    init() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectMCPServerTests-\(UUID().uuidString)", isDirectory: true)
        self.root = root
        self.workspaceRepository = FileSystemProjectWorkspaceRepository(rootDirectory: root)

        try? FileManager.default.createDirectory(
            at: root.appendingPathComponent("Docs"),
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources"),
            withIntermediateDirectories: true
        )

        try? "# Guide\n\nHello from guide. AlphaComponent.\n".write(
            to: root.appendingPathComponent("Docs/guide.md"),
            atomically: true,
            encoding: .utf8
        )
        try? "let alphaComponent = true\nprint(\"AlphaComponent\")\n".write(
            to: root.appendingPathComponent("Sources/App.swift"),
            atomically: true,
            encoding: .utf8
        )
        try? "Nothing to see here. AlphaComponent.\n".write(
            to: root.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

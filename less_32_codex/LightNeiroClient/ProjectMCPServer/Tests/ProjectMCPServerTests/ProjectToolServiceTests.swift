import MCP
import XCTest
@testable import ProjectMCPServer

final class ProjectToolServiceTests: XCTestCase {
    func testCurrentGitBranchToolReturnsBranchName() async {
        let repository = MockProjectRepository(
            branch: "feature/project-mcp",
            files: []
        )
        let service = ProjectToolService(
            getCurrentGitBranchUseCase: GetCurrentGitBranchUseCase(repository: repository),
            listProjectFilesUseCase: ListProjectFilesUseCase(repository: repository),
            getUncommittedChangesUseCase: GetUncommittedChangesUseCase(repository: repository)
        )

        let result = await service.callTool(
            name: ProjectToolCatalog.currentGitBranchToolName,
            arguments: [:]
        )

        XCTAssertFalse(result.isError ?? true)
        XCTAssertEqual(extractText(from: result.content), "feature/project-mcp")
    }

    func testListProjectFilesToolReturnsFormattedFileList() async {
        let repository = MockProjectRepository(
            branch: "main",
            files: [
                ProjectFile(relativePath: "Package.swift"),
                ProjectFile(relativePath: "Sources/ProjectMCPServer/main.swift")
            ]
        )
        let service = ProjectToolService(
            getCurrentGitBranchUseCase: GetCurrentGitBranchUseCase(repository: repository),
            listProjectFilesUseCase: ListProjectFilesUseCase(repository: repository),
            getUncommittedChangesUseCase: GetUncommittedChangesUseCase(repository: repository)
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
        let service = ProjectToolService(
            getCurrentGitBranchUseCase: GetCurrentGitBranchUseCase(repository: repository),
            listProjectFilesUseCase: ListProjectFilesUseCase(repository: repository),
            getUncommittedChangesUseCase: GetUncommittedChangesUseCase(repository: repository)
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

    private func extractText(from content: [Tool.Content]) -> String {
        content.compactMap { item in
            if case .text(let text) = item {
                return text
            }
            return nil
        }
        .joined(separator: "\n")
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

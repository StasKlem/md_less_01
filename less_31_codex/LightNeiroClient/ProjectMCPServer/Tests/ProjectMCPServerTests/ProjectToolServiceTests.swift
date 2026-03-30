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
            listProjectFilesUseCase: ListProjectFilesUseCase(repository: repository)
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
            listProjectFilesUseCase: ListProjectFilesUseCase(repository: repository)
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

    func currentGitBranch() throws -> String {
        branch
    }

    func listProjectFiles() throws -> [ProjectFile] {
        files
    }
}

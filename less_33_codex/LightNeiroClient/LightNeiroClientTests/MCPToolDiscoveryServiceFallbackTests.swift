import XCTest
@testable import LightNeiroClient

final class MCPToolDiscoveryServiceFallbackTests: XCTestCase {
    func testFetchCurrentGitBranchFallsBackToLocalGitWhenProjectMCPPathIsInvalid() async throws {
        let service = MCPToolDiscoveryService(
            projectEnvironmentProvider: {
                ["PROJECT_MCP_SERVER_PATH": "/definitely/missing/project-mcp-server"]
            }
        )

        let branch = try await service.fetchCurrentGitBranch(serverURL: URL(string: "stdio://project")!)

        XCTAssertFalse((branch.branch ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertNotNil(branch.diagnosticMessage)
    }

    func testFetchProjectFilesFallsBackToLocalGitWhenProjectMCPPathIsInvalid() async throws {
        let service = MCPToolDiscoveryService(
            projectEnvironmentProvider: {
                ["PROJECT_MCP_SERVER_PATH": "/definitely/missing/project-mcp-server"]
            }
        )

        let files = try await service.fetchProjectFiles(serverURL: URL(string: "stdio://project")!)

        XCTAssertFalse(files.files.isEmpty)
        XCTAssertTrue(files.files.contains("AGENTS.md"))
        XCTAssertTrue(files.files.contains("LightNeiroClient/ProjectMCPServer/Package.swift"))
        XCTAssertNotNil(files.diagnosticMessage)
    }

    func testFetchCurrentGitBranchAcceptsRepositoryRootAsProjectMCPPath() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        let service = MCPToolDiscoveryService(
            projectEnvironmentProvider: {
                ["PROJECT_MCP_SERVER_PATH": repositoryRoot]
            }
        )

        let branch = try await service.fetchCurrentGitBranch(serverURL: URL(string: "stdio://project")!)

        XCTAssertEqual(branch.branch, "main")
        XCTAssertNil(branch.diagnosticMessage)
    }
}

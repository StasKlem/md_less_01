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

        XCTAssertFalse(branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testFetchProjectFilesFallsBackToLocalGitWhenProjectMCPPathIsInvalid() async throws {
        let service = MCPToolDiscoveryService(
            projectEnvironmentProvider: {
                ["PROJECT_MCP_SERVER_PATH": "/definitely/missing/project-mcp-server"]
            }
        )

        let files = try await service.fetchProjectFiles(serverURL: URL(string: "stdio://project")!)

        XCTAssertFalse(files.isEmpty)
        XCTAssertTrue(files.contains("AGENTS.md"))
        XCTAssertTrue(files.contains("LightNeiroClient/ProjectMCPServer/Package.swift"))
    }
}

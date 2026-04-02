// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HackerNewsSummaryMCPServer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "HackerNewsSummaryMCPServer", targets: ["HackerNewsSummaryMCPServer"])
    ],
    dependencies: [
        .package(url: "https://github.com/msventurini/swift-mcp-sdk.git", from: "0.10.2")
    ],
    targets: [
        .executableTarget(
            name: "HackerNewsSummaryMCPServer",
            dependencies: [
                .product(name: "MCP", package: "swift-mcp-sdk")
            ]
        ),
        .testTarget(
            name: "HackerNewsSummaryMCPServerTests",
            dependencies: ["HackerNewsSummaryMCPServer"]
        )
    ]
)

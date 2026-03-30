// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HackerNewsArchiveMCPServer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "HackerNewsArchiveMCPServer", targets: ["HackerNewsArchiveMCPServer"])
    ],
    dependencies: [
        .package(url: "https://github.com/msventurini/swift-mcp-sdk.git", from: "0.10.2")
    ],
    targets: [
        .executableTarget(
            name: "HackerNewsArchiveMCPServer",
            dependencies: [
                .product(name: "MCP", package: "swift-mcp-sdk")
            ]
        ),
        .testTarget(
            name: "HackerNewsArchiveMCPServerTests",
            dependencies: ["HackerNewsArchiveMCPServer"]
        )
    ]
)

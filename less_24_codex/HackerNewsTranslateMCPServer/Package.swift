// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HackerNewsTranslateMCPServer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "HackerNewsTranslateMCPServer", targets: ["HackerNewsTranslateMCPServer"])
    ],
    dependencies: [
        .package(url: "https://github.com/msventurini/swift-mcp-sdk.git", from: "0.10.2")
    ],
    targets: [
        .executableTarget(
            name: "HackerNewsTranslateMCPServer",
            dependencies: [
                .product(name: "MCP", package: "swift-mcp-sdk")
            ]
        ),
        .testTarget(
            name: "HackerNewsTranslateMCPServerTests",
            dependencies: ["HackerNewsTranslateMCPServer"]
        )
    ]
)

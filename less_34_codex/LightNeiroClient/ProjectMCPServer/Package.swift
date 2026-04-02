// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ProjectMCPServer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "ProjectMCPServer",
            targets: ["ProjectMCPServer"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/msventurini/swift-mcp-sdk.git", from: "0.10.2")
    ],
    targets: [
        .executableTarget(
            name: "ProjectMCPServer",
            dependencies: [
                .product(name: "MCP", package: "swift-mcp-sdk")
            ]
        ),
        .testTarget(
            name: "ProjectMCPServerTests",
            dependencies: ["ProjectMCPServer"]
        )
    ]
)

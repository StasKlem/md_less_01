// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenWeatherMCPServer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "OpenWeatherMCPServer", targets: ["OpenWeatherMCPServer"])
    ],
    dependencies: [
        .package(url: "https://github.com/msventurini/swift-mcp-sdk.git", from: "0.10.2")
    ],
    targets: [
        .executableTarget(
            name: "OpenWeatherMCPServer",
            dependencies: [
                .product(name: "MCP", package: "swift-mcp-sdk")
            ]
        ),
        .testTarget(
            name: "OpenWeatherMCPServerTests",
            dependencies: ["OpenWeatherMCPServer"]
        )
    ]
)

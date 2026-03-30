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
    targets: [
        .executableTarget(
            name: "ProjectMCPServer"
        )
    ]
)

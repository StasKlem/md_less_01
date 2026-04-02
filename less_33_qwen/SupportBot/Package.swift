// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "SupportBot",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(
            name: "SupportBot",
            targets: ["SupportBot"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/steipete/TauTUI.git", exact: "0.1.5")
    ],
    targets: [
        .executableTarget(
            name: "SupportBot",
            dependencies: [
                .product(name: "TauTUI", package: "TauTUI")
            ],
            path: "SupportBot"
        )
    ]
)

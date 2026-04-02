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
        // TUI фреймворк
        .package(url: "https://github.com/steipete/TauTUI.git", exact: "0.1.5"),
        // HTTP клиент для LLM API
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.20.0"),
        // SQLite для хранения истории и векторов
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.0"),
        // YAML парсинг для конфигурации
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        // Логирование
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "SupportBot",
            dependencies: [
                .product(name: "TauTUI", package: "TauTUI"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "SQLite", package: "SQLite.swift"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "SupportBot"
        )
    ]
)

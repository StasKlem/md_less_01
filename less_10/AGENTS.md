# AGENTS.md - MacTerminalOpencode

Guidelines for agentic coding agents working in this repository.

## Project Overview

This is a native macOS application built with Swift and Cocoa (AppKit). The project uses Xcode as the primary build system.

- **Language**: Swift 5.0
- **Platform**: macOS 13.0+
- **UI Framework**: Cocoa (AppKit)
- **Bundle ID**: StasKlem.MacTerminalOpencode
- **Architecture**: Clean Architecture with SOLID principles

## Project Structure (Clean Architecture)

```
MacTerminalOpencode/
├── MacTerminalOpencode/
│   ├── App/
│   │   ├── AppDelegate.swift       # Application lifecycle
│   │   ├── Constants.swift          # App constants
│   │   └── main.swift              # Entry point
│   ├── Domain/
│   │   ├── Entities/                # Business models
│   │   │   ├── Message.swift
│   │   │   ├── ChatSession.swift
│   │   │   ├── LLMSettings.swift
│   │   │   ├── StreamingChunk.swift
│   │   │   ├── AppError.swift
│   │   │   ├── SummarizationStrategy.swift
│   │   │   └── ConversationSummaryStorageProtocol.swift
│   │   └── UseCases/               # Business logic
│   │       ├── SendMessageUseCase.swift
│   │       ├── FetchModelsUseCase.swift
│   │       ├── ChatBehaviorStrategy.swift
│   │       ├── BasicChatStrategy.swift
│   │       ├── SummarizationChatStrategy.swift
│   │       └── SummarizationService.swift
│   ├── Data/
│   │   ├── Network/
│   │   │   ├── LLMAPIClient.swift
│   │   │   ├── NetworkManager.swift
│   │   │   └── SSEParser.swift
│   │   └── Storage/
│   │       ├── ChatStorage.swift
│   │       ├── SettingsStorage.swift
│   │       ├── KeychainService.swift
│   │       └── ConversationSummaryStorage.swift
│   ├── ViewModels/
│   │   ├── ChatViewModel.swift
│   │   ├── SettingsViewModel.swift
│   │   └── MetricsViewModel.swift
│   └── UI/
│       ├── Views/
│       │   ├── ChatPanelViewController.swift
│       │   ├── SettingsPanelViewController.swift
│       │   └── MetricsPanelViewController.swift
│       ├── Components/
│       │   └── MarkdownAttributedString.swift
│       └── SplitView/
│           └── MainSplitViewController.swift
```

## Build/Lint/Test Commands

### Building

```bash
# Build the project (Debug)
xcodebuild -project MacTerminalOpencode/MacTerminalOpencode.xcodeproj -scheme MacTerminalOpencode -configuration Debug build

# Build the project (Release)
xcodebuild -project MacTerminalOpencode/MacTerminalOpencode.xcodeproj -scheme MacTerminalOpencode -configuration Release build

# Build from project directory
cd MacTerminalOpencode && xcodebuild -scheme MacTerminalOpencode build
```

### Running

```bash
# Run the app (requires build first)
open MacTerminalOpencode/build/Debug/MacTerminalOpencode.app

# Or run via Xcode
open MacTerminalOpencode/MacTerminalOpencode.xcodeproj
```

### Testing

```bash
# Run all tests
xcodebuild -project MacTerminalOpencode/MacTerminalOpencode.xcodeproj -scheme MacTerminalOpencode test

# Run a single test file
xcodebuild -project MacTerminalOpencode/MacTerminalOpencode.xcodeproj -scheme MacTerminalOpencode test -only-testing:MacTerminalOpencodeTests/TestFileName

# Run a single test method
xcodebuild -project MacTerminalOpencode/MacTerminalOpencode.xcodeproj -scheme MacTerminalOpencode test -only-testing:MacTerminalOpencodeTests/TestFileName/testMethodName

# Run tests with verbose output
xcodebuild -project MacTerminalOpencode/MacTerminalOpencode.xcodeproj -scheme MacTerminalOpencode test -destination 'platform=macOS' | xcpretty
```

### Linting

```bash
# SwiftLint (if installed)
swiftlint --path MacTerminalOpencode/MacTerminalOpencode

# SwiftLint autocorrect
swiftlint --path MacTerminalOpencode/MacTerminalOpencode --autocorrect
```

### Clean

```bash
# Clean build folder
xcodebuild -project MacTerminalOpencode/MacTerminalOpencode.xcodeproj -scheme MacTerminalOpencode clean

# Clean derived data
rm -rf ~/Library/Developer/Xcode/DerivedData/MacTerminalOpencode-*
```

## Code Style Guidelines

### Naming Conventions

- **Classes/Structs/Enums/Protocols**: PascalCase (`AppDelegate`, `ViewController`)
- **Variables/Constants/Functions**: camelCase (`viewDidLoad`, `sendMessage`)
- **File names**: Match the primary type (`AppDelegate.swift`, `ChatViewModel.swift`)
- **File headers**: Include creation date and author

```swift
//
//  FileName.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 26.02.2026.
//
```

### Formatting

- **Indentation**: 4 spaces (no tabs)
- **Line length**: Prefer 120 characters max
- **Braces**: Opening brace on same line
- **Blank lines**: Between method groups, before/after MARK comments

### Imports

Order: Foundation → macOS frameworks → third-party → local

```swift
import Foundation
import Cocoa

// Third-party
import Alamofire

// Local
import MyLocalModule
```

### Error Handling

- Use `throw` for recoverable errors
- Use `Result` type for async/callback-based operations
- Prefer `guard` statements for early exits
- Use `AppError` enum for application-specific errors

```swift
enum AppError: Error {
    case invalidURL
    case networkError(String)
    case invalidResponse
}
```

### Protocols and Dependency Injection

- Use protocols for abstraction (Dependency Inversion Principle)
- Inject dependencies through initializers
- Name protocols with `Protocol` suffix for implementations

```swift
protocol SummarizationServiceProtocol {
    func createSummary(...) async throws -> (...)
}

final class SummarizationService: SummarizationServiceProtocol {
    private let apiClient: LLMAPIClientProtocol
    
    init(apiClient: LLMAPIClientProtocol) {
        self.apiClient = apiClient
    }
}
```

### Strategy Pattern

- Use protocols for behavior strategies
- Concrete strategies implement the protocol
- Configure strategies at runtime based on settings

```swift
protocol ChatBehaviorStrategy: AnyObject {
    var summarizationService: SummarizationServiceProtocol? { get set }
    var settings: LLMSettings { get set }
    
    func prepareMessages(session: ChatSession, systemPrompt: String) async -> [[String: String]]
    func createSummaryIfNeeded(...) async
}
```

### MARK Comments

Use `MARK:` comments to organize code sections:

```swift
// MARK: - Properties
// MARK: - Initialization
// MARK: - Public Methods
// MARK: - Private Methods
// MARK: - Actions
// MARK: - NSTableViewDataSource
// MARK: - NSTableViewDelegate
```

### Optionals

- Prefer `if let` or `guard let` over forced unwrap
- Use `??` for default values

### Closures

- Use trailing closure syntax
- Capture `self` explicitly using `[weak self]` to prevent retain cycles

```swift
Task { [weak self] in
    guard let self = self else { return }
    // Use self
}
```

## Architecture Principles

### Clean Architecture Layers

1. **Domain Layer**: Entities, UseCases (business logic)
2. **Data Layer**: Network, Storage (data access)
3. **ViewModels Layer**: Presentation logic
4. **UI Layer**: Views, Controllers

### SOLID Principles

- **S**ingle Responsibility: Each class has one reason to change
- **O**pen/Closed: Open for extension, closed for modification
- **L**iskov Substitution: Subtypes must be substitutable
- **I**nterface Segregation: Many small protocols vs one large
- **D**ependency Inversion: Depend on abstractions, not concretions

## Additional Notes

- This project uses App Sandbox with read-only user-selected files access
- Hardened Runtime is enabled
- Swift strict concurrency checking is enabled
- Main actor isolation is the default

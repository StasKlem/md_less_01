# AGENTS.md - MacTerminalOpencode

Guidelines for agentic coding agents working in this repository.

## Project Overview

This is a native macOS application built with Swift and Cocoa (AppKit). The project uses Xcode as the primary build system.

- **Language**: Swift 5.0
- **Platform**: macOS 26.2+
- **UI Framework**: Cocoa (AppKit) with Storyboards
- **Bundle ID**: StasKlem.MacTerminalOpencode

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

# Run a single test file (replace TestFileName with actual test class name)
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

# Swift compiler warnings as errors (in Debug)
xcodebuild -project MacTerminalOpencode/MacTerminalOpencode.xcodeproj -scheme MacTerminalOpencode -configuration Debug build SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
```

### Clean

```bash
# Clean build folder
xcodebuild -project MacTerminalOpencode/MacTerminalOpencode.xcodeproj -scheme MacTerminalOpencode clean

# Clean build folder and derived data
xcodebuild -project MacTerminalOpencode/MacTerminalOpencode.xcodeproj -scheme MacTerminalOpencode clean && rm -rf ~/Library/Developer/Xcode/DerivedData/MacTerminalOpencode-*
```

## Code Style Guidelines

### File Organization

```
MacTerminalOpencode/
├── MacTerminalOpencode/
│   ├── AppDelegate.swift          # Application lifecycle
│   ├── ViewController.swift       # Main view controller
│   ├── Models/                    # Data models
│   ├── Views/                     # Custom views
│   ├── Controllers/               # Additional view controllers
│   ├── Services/                  # Business logic services
│   ├── Extensions/                # Swift extensions
│   ├── Utils/                     # Utility classes/functions
│   ├── Resources/                 # Assets, xibs, storyboards
│   └── Supporting Files/          # Info.plist, entitlements
```

### Imports

```swift
// Order: Foundation -> macOS frameworks -> third-party -> local
import Cocoa
import Foundation

// Separate groups with blank lines
import Cocoa

import Alamofire  // Third-party

import MyLocalModule  // Local
```

### Naming Conventions

- **Classes/Structs/Enums/Protocols**: PascalCase (`AppDelegate`, `ViewController`)
- **Variables/Constants/Functions**: camelCase (`viewDidLoad`, `applicationDidFinishLaunching`)
- **File names**: Match the primary type (`AppDelegate.swift`, `ViewController.swift`)
- **File headers**: Include creation date and author

```swift
//
//  FileName.swift
//  MacTerminalOpencode
//
//  Created by [Author] on [Date].
//
```

### Formatting

- **Indentation**: 4 spaces (no tabs)
- **Line length**: Prefer 120 characters max
- **Braces**: Opening brace on same line
- **Blank lines**: Between method groups, before/after MARK comments

```swift
class ExampleClass {
    
    // MARK: - Properties
    
    private var exampleProperty: String?
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    // MARK: - Private Methods
    
    private func setupUI() {
        // Implementation
    }
}
```

### Types and Annotations

- Use explicit type annotations for properties and public interfaces
- Use type inference for local variables when clear

```swift
// Properties - explicit type
private let titleLabel: NSTextField
private var dataItems: [DataItem] = []

// Local variables - inference preferred
let items = fetchDataItems()
let count = items.count
```

### Error Handling

- Use `throw` for recoverable errors
- Use `Result` type for async/callback-based operations
- Prefer guard statements for early exits

```swift
// Throwing function
func loadData() throws -> Data {
    guard let url = URL(string: "path") else {
        throw DataError.invalidURL
    }
    return try Data(contentsOf: url)
}

// Guard for early exit
func processData(_ data: Data?) {
    guard let data = data else {
        print("No data available")
        return
    }
    // Process data
}

// Result type
func fetchItems(completion: @escaping (Result<[Item], Error>) -> Void) {
    // Implementation
}
```

### MARK Comments

Use `MARK:` comments to organize code sections:

```swift
// MARK: - Properties
// MARK: - Lifecycle
// MARK: - Public Methods
// MARK: - Private Methods
// MARK: - Actions
// MARK: - NSTableViewDataSource
// MARK: - NSTableViewDelegate
```

### Optionals

- Prefer `if let` or `guard let` over forced unwrap
- Use `??` for default values
- Avoid implicitly unwrapped optionals unless required (IBOutlets are acceptable)

```swift
// Preferred
if let name = user.name {
    print(name)
}

// With default
let displayName = user.name ?? "Unknown"

// Guard
guard let data = response.data else {
    return
}
```

### Closures

- Use trailing closure syntax
- Capture self explicitly when needed
- Use weak/unowned to prevent retain cycles

```swift
// Trailing closure
fetchData { result in
    self.handleResult(result)
}

// Capture list
service.execute { [weak self] response in
    guard let self = self else { return }
    self.updateUI(with: response)
}
```

### Project Structure Conventions

- **AppDelegate**: Handle application lifecycle events only
- **ViewController**: Manage single view/screen, delegate to services
- **Models**: Plain data structures, Codable for persistence
- **Services**: Singleton or injected dependencies for business logic
- Use protocols for abstraction and testability

### macOS-Specific Guidelines

- Use AppKit (not UIKit) - prefix classes with `NS`
- Use Storyboards or programmatic UI (consistent within project)
- Respect App Sandbox restrictions
- Support dark mode with semantic colors
- Use Auto Layout for responsive layouts

## Testing Conventions

- Test files in `MacTerminalOpencodeTests/` directory
- Test class naming: `[ClassName]Tests`
- Test method naming: `test_[method]_[scenario]_[expectedResult]`

```swift
func test_loadData_whenValidURL_returnsData() {
    // Given
    let sut = DataLoader()
    
    // When
    let result = sut.loadData()
    
    // Then
    XCTAssertNotNil(result)
}
```

## Additional Notes

- This project uses App Sandbox with read-only user-selected files access
- Hardened Runtime is enabled
- Swift strict concurrency checking is enabled (`SWIFT_APPROACHABLE_CONCURRENCY = YES`)
- Main actor isolation is the default (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`)

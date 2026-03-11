# Architecture Templates

Use these templates as starting points. Keep names feature-specific.

## Use Case Protocol and Implementation

```swift
public protocol SaveProfileUseCase {
    func execute(request: SaveProfileRequest) async throws -> SaveProfileResult
}

public struct SaveProfileRequest: Equatable {
    public let userID: String
    public let displayName: String
}

public struct SaveProfileResult: Equatable {
    public let updatedAt: Date
}

public protocol ProfileRepository {
    func updateProfile(userID: String, displayName: String) async throws -> Date
}

public final class DefaultSaveProfileUseCase: SaveProfileUseCase {
    private let repository: ProfileRepository

    public init(repository: ProfileRepository) {
        self.repository = repository
    }

    public func execute(request: SaveProfileRequest) async throws -> SaveProfileResult {
        let date = try await repository.updateProfile(
            userID: request.userID,
            displayName: request.displayName
        )
        return SaveProfileResult(updatedAt: date)
    }
}
```

## Adapter Skeleton

```swift
public final class RemoteProfileRepository: ProfileRepository {
    private let client: HTTPClient

    public init(client: HTTPClient) {
        self.client = client
    }

    public func updateProfile(userID: String, displayName: String) async throws -> Date {
        // Map domain intent to transport request and back.
        let request = UpdateProfileRequestDTO(userID: userID, displayName: displayName)
        let response = try await client.send(request)
        return response.updatedAt
    }
}
```

## AppKit MVVM ViewModel Skeleton

```swift
@MainActor
public final class ProfileViewModel {
    public struct ViewState: Equatable {
        public var displayName: String
        public var isSaving: Bool
        public var errorMessage: String?
    }

    public private(set) var state: ViewState
    private let saveProfileUseCase: SaveProfileUseCase

    public init(
        initialName: String,
        saveProfileUseCase: SaveProfileUseCase
    ) {
        self.state = ViewState(displayName: initialName, isSaving: false, errorMessage: nil)
        self.saveProfileUseCase = saveProfileUseCase
    }

    public func didChangeDisplayName(_ name: String) {
        state.displayName = name
    }

    public func didTapSave(userID: String) async {
        state.isSaving = true
        state.errorMessage = nil

        defer { state.isSaving = false }

        do {
            _ = try await saveProfileUseCase.execute(
                request: SaveProfileRequest(userID: userID, displayName: state.displayName)
            )
        } catch {
            state.errorMessage = "Unable to save profile."
        }
    }
}
```

## Architecture Review Checklist

Use this checklist for refactor/review output:

1. Is any business logic in view controllers or adapters?
2. Do use cases depend only on abstractions?
3. Are repository/service ports cohesive and minimal?
4. Is mapping logic duplicated across layers?
5. Are async/error paths explicit and testable?
6. Are view models tested for state transitions?
7. Can infrastructure be swapped without domain changes?

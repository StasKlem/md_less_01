# AGENTS.md

## Engineering Rules (Mandatory)

All code in this project must follow:
- SOLID principles
- DRY principle
- Clean Architecture
- Project target: macOS
- Programming language: Swift
- UI architecture: MVVM
- Do not use SwiftUI
- Build UI with code only (no Interface Builder, no Storyboards, no XIB)

## Clean Architecture

- Keep business logic in inner layers (domain/use cases), not in frameworks or transport code.
- Keep dependency direction inward only (outer layers depend on inner layers).
- Access external systems (DB, HTTP, queues, files) through interfaces/ports.
- Implement interfaces in outer layers (adapters/infrastructure), not in domain.
- Do not couple domain logic to frameworks or storage details.

## SOLID

- Single Responsibility: each module/type/function has one clear reason to change.
- Open/Closed: extend behavior without modifying stable core logic where possible.
- Liskov Substitution: implementations must preserve contract behavior.
- Interface Segregation: prefer small focused interfaces over wide "god interfaces".
- Dependency Inversion: high-level logic depends on abstractions, not concrete adapters.

## DRY

- Do not duplicate business rules, validation, or mapping logic.
- Extract shared logic only when duplication is real and semantic.
- Keep one source of truth for domain invariants and contracts.

## Code Quality Expectations

- Prefer composition over inheritance.
- Keep functions small, explicit, and testable.
- Handle errors explicitly; do not swallow errors silently.
- Avoid hidden side effects and global mutable state.
- Keep public APIs minimal and intention-revealing.

## Testing

- Add or update tests for each behavior change.
- Cover success, edge, and failure scenarios.
- Ensure architecture boundaries are testable and preserved by tests/reviews.

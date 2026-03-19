---
name: swift-software-architect
description: Architect, refactor, and review Swift macOS applications using SOLID, DRY, Clean Architecture, and MVVM with code-only UI (AppKit/UIKit, no SwiftUI, no Storyboards/XIB). Use when defining project structure, splitting responsibilities, introducing protocols and use cases, enforcing dependency inversion, planning module boundaries, or producing architecture-focused code reviews and migration plans.
---

# Swift Software Architect

Apply this workflow for each architecture task.

## 1) Audit Constraints First

Capture and preserve hard constraints before proposing structure:
- Target OS is `macOS`.
- Use `Swift`.
- Build UI with code only.
- Use `MVVM`.
- Do not use `SwiftUI`.
- Do not use Storyboards or XIB.
- Keep business logic framework-agnostic.

If constraints are missing, assume the above defaults.

## 2) Define Architectural Boundaries

Partition solution into these layers:
- `Domain` for entities, value objects, and business rules.
- `Application` for use cases and ports.
- `Infrastructure` for API/storage/adapters.
- `Presentation` for AppKit/UI state and view models.

Enforce dependency rule:
- Outer layers depend on inner layers.
- Inner layers depend only on abstractions or pure domain types.

Reject any direct dependency from domain/use case code to AppKit, network clients, persistence SDKs, or system singletons.

## 3) Model Ports and Use Cases

For each feature slice:
1. Define a use case protocol in `Application` (input/output focused).
2. Define small repository/service ports needed by the use case.
3. Implement orchestration in a use case class or struct.
4. Inject ports via initializer.
5. Keep mapping logic near use case boundary, not in UI.

Keep interfaces narrow. Split broad protocols into focused contracts.

## 4) Connect MVVM in Presentation Layer

Apply these rules:
- Keep `ViewController` focused on rendering and forwarding user intent.
- Keep state transitions and coordination in `ViewModel`.
- Expose intent methods (`onAppear`, `didTapSave`, etc.) and immutable view state.
- Avoid business decisions inside controllers.
- Convert domain/application results into display models in view model mapper methods.

## 5) Enforce SOLID + DRY with a Review Gate

Use this architecture gate before finishing:
1. Single responsibility: each type has one reason to change.
2. Open/closed: extend with new adapters/use cases without rewriting stable core.
3. Liskov substitution: each implementation honors protocol behavior.
4. Interface segregation: no consumer depends on unused methods.
5. Dependency inversion: high-level policy depends on protocols.
6. DRY: no repeated invariants, validation, or mapping rules.

## 6) Produce Deliverables in This Order

When asked to design or refactor, deliver:
1. Boundary map (layers and dependencies).
2. Protocol list (ports and use cases).
3. File/module placement plan.
4. Incremental migration steps.
5. Test plan by layer:
   - Domain rule tests
   - Use case unit tests with test doubles
   - View model state transition tests
   - Adapter integration tests for I/O boundaries

## 7) Use Templates When Implementing

Load [references/architecture-templates.md](references/architecture-templates.md) when you need starter structures for:
- Use case protocol + implementation
- Repository port + adapter
- View model skeleton for AppKit MVVM
- Architecture review checklist format

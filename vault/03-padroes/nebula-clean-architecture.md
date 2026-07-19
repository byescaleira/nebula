---
tags: [pattern, architecture, clean-architecture, swift6, nebula]
aliases: [Clean Architecture in Swift, Nebula architecture toolkit, Uncle Bob layers Nebula]
related: [[nebula-spm-architecture]], [[nebula-swift6-concurrency]], [[nebula-errors]]
---

# Clean Architecture → Swift 6 (Nebula architecture toolkit)

Synthesis of Uncle Bob's Clean Architecture layers + dependency rule mapped onto Nebula's Swift 6 surface (Foundation-only, no UIKit/SwiftUI, no `@MainActor` default, `Sendable` value types + protocols + actors). Source of truth: root docs (`ARCHITECTURE.md`, `DECISIONS.md`, `CLAUDE.md`); this is the synthesis/navigation layer.

## The dependency rule (verbatim)

> "Source code dependencies can only point inwards." — Uncle Bob, [The Clean Architecture](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html).

Inner circles know nothing of outer circles — no named entity, no data format. Boundaries are crossed via the **Dependency Inversion Principle**: the inner layer owns an interface (port); the outer layer implements it. "We have the use case call an interface (Use Case Output Port) in the inner circle, and have the presenter in the outer circle implement it." Data crossing boundaries is "simple data structures" / DTOs — never Entities or DB rows.

## Layer → Swift 6 construct map

| Uncle Bob layer | Nebula / Swift 6 construct |
|---|---|
| **Entities** (enterprise rules) | `Sendable` value structs (pure, `Equatable`/`Hashable` derived); stateful enterprise rules → `actor`. No framework deps. Marker protocol `NebulaEntity` (Sendable). |
| **Use Cases** (application rules) | `NebulaUseCase` `Sendable` protocol — `associatedtype Input/Output: Sendable`, `@Sendable func execute(_:)` (sync + async overloads), untyped `throws` (SE-0413). Concrete: `Sendable struct` (stateless, holds port protocols in `let`) or `actor` (stateful orchestration). Constructor injection of ports. |
| **Interface Adapters** | `NebulaInputPort` / `NebulaOutputPort` / `NebulaRepository` / `NebulaGateway` `Sendable` protocols **owned by Nebula (inner)**, implemented by the app (outer). `NebulaDTO` marker (Sendable plain struct) for boundary data. Repository = Fowler's [Repository](https://martinfowler.com/eaaCatalog/repository.html) pattern (collection-like, async-throwing accessors); Gateway = Fowler's [Gateway](https://martinfowler.com/eaaCatalog/gateway.html) (encapsulates an external system). |
| **Frameworks & Drivers** | Outside Nebula entirely. Nebula ships only the seams (protocols + DTO marker + a lightweight composition root). The app owns DB/Web/CoreData concrete adapters. |

## Dependency-rule enforcement is the hard problem

Single SPM target = `internal` access can't enforce inward-only across files ("internal is a promise; a separate module is a law" — cf. the [Medium case study](https://medium.com/codetodeploy/the-breakthrough-how-a-tech-lead-modernized-a-150-file-1e6e0b3f72a4)). Nebula encodes the rule **by protocol ownership**: ports are defined in Nebula (inner), concrete adapters in the app (outer). Real compile-time enforcement requires the app to put entities/use-cases in a **separate SPM module** that depends on Nebula while adapters depend on that module. Nebula documents the template; it does not (cannot, as a single target) enforce it at compile time. → see Risks.

## DI without a DI framework

`dependencies: []` forbids Resolver/Factory/Swinject. Mirror the existing [[nebula-errors]] `Mutex<NebulaErrorConfiguration>` accessor pattern: a lightweight `NebulaCompositionRoot` holds port→`@Sendable` factory bindings in a `Mutex<[PartialKeyPath: @Sendable () -> Any]>`-style table and resolves via a generic `resolve(_:​as:)`. **NOT a DI container** with scoping/resolution graphs — that is a framework. Primary path = explicit-parameter constructor injection (testable); the composition root is the ergonomic seam at the app boundary only.

## Sendable strategy (per type)

- Entities: derived `Sendable` (all-value fields); `actor` for stateful enterprise rules (isolation is the synchronization, no `@unchecked`).
- Use cases: `Sendable struct` (stateless) or `actor` (stateful); `Input`/`Output` `Sendable`; `execute` is `@Sendable` and may be `async throws`.
- Ports: `Sendable` protocols (so a port-typed `let` in a `Sendable` use case is valid; concrete adapters must be `Sendable` — `actor` or `Sendable struct`).
- DTOs: derived `Sendable` value structs; never carry `any Error` (use `NebulaError`).
- Composition root: `Mutex`-backed (`let`), `@Sendable` factory closures; no `@unchecked`.

## Typed throws

Public use-case `execute` uses untyped `throws` (evolution safety, SE-0413). Consumers opt into `Result<Output, NebulaError>` via `NebulaError.wrap(_:)` (existing). Errors crossing actor boundaries (use case → presenter port, repository → use case) MUST be `Sendable` → `NebulaError` (concrete `Sendable: Error`), not `any Error`.

## Out of scope

Presentation patterns (MVVM/MVC/VIP/VIPER) are explicitly out of scope for this research — Nebula presents nothing; Cosmos owns UI. `NebulaOutputPort` is the seam a presenter implements, but Nebula defines no presenter/view/viewmodel types.

## Open questions

- Should Nebula ship a multi-module SPM template (entities + use-cases as a separate product) to give compile-time dependency-rule enforcement, or stay single-target and document the convention?
- Should `NebulaUseCase.execute` carry an `associatedtype Failure: Error = NebulaError` for typed-throws consumers, or keep untyped `throws` only?
- Should `NebulaRepository` expose a typed-query surface (Fowler "query specifications") or just `func get(_ id: ID) async throws -> Entity`-style accessors for v1?

## Risks

- Protocol-ownership is convention, not compile-time enforcement, within a single SPM target. App discipline required; regression risk if adapters leak into an inner module.
- A composition root can quietly grow into a DI container (scoping, resolution graphs) — scope creep toward a forbidden framework. Keep it to factory bindings only.
- `Sendable` protocols with `associatedtype`s resist `any Port` storage; the composition root may need type-erased factories (`@Sendable () -> Any` + `as!`), which is a code smell but unavoidable without generics gymnastics.
- Fowler's Repository as a `Sendable` protocol with async accessors pushes every concrete repo toward `actor`; apps with synchronous CoreData/SQLite stacks may chafe.

## Sources

- Uncle Bob, [The Clean Architecture](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html) (layers, dependency rule, DIP, output port/presenter, DTO boundary data).
- Martin Fowler, [Repository](https://martinfowler.com/eaaCatalog/repository.html), [Gateway](https://martinfowler.com/eaaCatalog/gateway.html), [PoEAA catalog](https://martinfowler.com/eaaCatalog/).
- Existing Nebula patterns: `NebulaError` / `NebulaErrorConfiguration` / `NebulaErrorConfig` (`Sources/Nebula/Errors/`), `NebulaStandards` (`Sources/Nebula/Standardize/`).
- Swift 6 surface: `Mutex`/`Atomic` (`Synchronization`), `Clock`/`AsyncStream` (`_Concurrency`) — **needs interface verify** against the Xcode 27 Beta 3 `.swiftinterface` before any API claim is shipped.
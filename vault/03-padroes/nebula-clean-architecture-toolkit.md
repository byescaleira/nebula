---
tags: [padroes, architecture, clean-architecture, swift6, nebula, toolkit]
aliases: [Nebula Clean Architecture Toolkit, clean-architecture-toolkit, Nebula architecture toolkit surface]
related: [[nebula-clean-architecture]], [[nebula-usecase]], [[nebula-repository]], [[nebula-domain-error]], [[nebula-registry-di]], [[nebula-test-doubles]], [[nebula-validation-invariants]], [[nebula-async-flow]], [[nebula-error-taxonomy-toolkit]], [[nebula-errors]], [[nebula-swift6-concurrency]], [[nebula-spm-architecture]]
status: shipped
shipped: "0.2.0"
---

# Nebula Clean Architecture Toolkit — Canonical Surface

The canonical map of the Nebula architecture toolkit: Uncle Bob's Clean Architecture layers + dependency rule mapped onto Nebula's Swift 6 surface, with the full toolkit type table and a Sendable strategy per type. This is the navigation hub for the toolkit notes ([[nebula-usecase]], [[nebula-repository]], [[nebula-domain-error]], [[nebula-registry-di]], [[nebula-test-doubles]], [[nebula-validation-invariants]], [[nebula-async-flow]]). The short layer-mapping primer is [[nebula-clean-architecture]]; this note is the comprehensive surface table. Source of truth = root docs (`ARCHITECTURE.md`, `DECISIONS.md`, `CLAUDE.md`, `VERSIONING.md`); this note is the synthesis. On conflict, the root doc wins.

## What Nebula is today (and is not)

`ARCHITECTURE.md:5` — "Nebula is a multi-platform Swift **foundation/architecture** library." Today only the *foundation* half exists: `Nebula.swift` top-level + `Logging`/`Errors`/`Extensions`/`Standardize`/`Measure` (`Sources/Nebula/` tree — verified, no `Architecture/` dir). The *architecture* half is the toolkit this note specifies: the seams (protocols + markers + DTO contract + a wiring helper) that let an app implement Clean Architecture efficiently, **without** Nebula owning any presentation, DB, or framework code. Presentation patterns (MVVM/MVC/VIP/VIPER) are **explicitly out of scope** — Nebula presents nothing; Cosmos owns UI.

## The dependency rule (verbatim-verified)

> "Source code dependencies can only point inwards." — Uncle Bob, [The Clean Architecture](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html).

Inner circles know nothing of outer circles — no named entity, no data format. The flow-of-control vs. dependency-rule contradiction is resolved by the **Dependency Inversion Principle**: "we have the use case call an interface (Use Case Output Port) in the inner circle, and have the presenter in the outer circle implement it." Data crossing boundaries is "simple data structures" / DTOs — "We don't want to cheat and pass Entities or Database rows." All three quotes verified verbatim against the blog in the research verify pass. Swift mapping: **the inner layer owns the protocol; the outer layer conforms** — Swift protocols express DIP directly.

## Layer → Swift 6 construct map

| Uncle Bob layer | Nebula construct | Owned by |
|---|---|---|
| **Entities** (enterprise rules) | `NebulaValue` / `NebulaEntity` / `NebulaAggregate` markers (Sendable value structs; `actor` for stateful enterprise rules); `NebulaID<Entity>` typed IDs | Nebula (inner) |
| **Use Cases** (application rules) | `NebulaUseCase<I, O>` generic Sendable struct over a `@Sendable (I) async throws -> O` body; `NebulaUseCaseRole` (command/query); `.decorate`/`.logged`/`.measured`/`.reported`/`.instrumented` | Nebula (inner) |
| **Interface Adapters** | `NebulaInputPort` / `NebulaOutputPort` Sendable marker ports; `NebulaRepository<Element>` + `NebulaReadOnlyRepository` / `NebulaWritableRepository` / `NebulaDeletableRepository` capability protocols; `NebulaGateway` + `NebulaGatewayConfiguration`/`NebulaGatewayConfig`; `NebulaDTO` marker | Nebula (inner, protocols only) |
| **Frameworks & Drivers** | Concrete repos (CoreData/SQLite/URLSession), concrete gateways, presenters/views | **App** (outer) |

Nebula ships **only the seams** (inner protocols + markers + DTO contract + a wiring helper). Concrete adapters live in the app. No SQL/CoreData/URLSession symbols in Nebula (URLSession appears only behind the optional `NebulaHTTPGateway` helper, which is Foundation).

## Toolkit surface table

| Type | Kind | Sendable strategy | Note |
|---|---|---|---|
| `NebulaValue` | marker protocol : `Sendable, Equatable, Hashable` | derived (conforming structs synthesize when fields are Sendable/Eq/Hash) | [[nebula-validation-invariants]] |
| `NebulaEntity` | protocol : `Sendable, Identifiable where ID: Sendable` (NOT `Equatable`) | derived; `let id` satisfies `Identifiable`'s get-only `var id: Self.ID` | [[nebula-validation-invariants]] |
| `NebulaAggregate` | marker protocol : `NebulaEntity` (no extra requirements) | inherited | [[nebula-validation-invariants]] |
| `NebulaID<Entity>` | generic Sendable struct (phantom-typed), `: NebulaValue` | derived (`Raw: Sendable, Hashable`) | [[nebula-validation-invariants]] |
| `NebulaDTO` | marker protocol : `Sendable` (recommended `Equatable`) | derived (plain value fields; never `any Error`) | this note |
| `NebulaUseCaseBody<I, O>` | `typealias @Sendable (I) async throws -> O` | the closure's own `@Sendable` | [[nebula-usecase]] |
| `NebulaUseCaseRole` | closed `enum : String, Sendable { case command, query }` | derived (no payloads) | [[nebula-usecase]] |
| `NebulaUseCase<I, O>` | generic `struct : Sendable where I: Sendable, O: Sendable` (NOT `Equatable` — `@Sendable` body) | derived (`name: StaticString`, `role`, `body` all Sendable) | [[nebula-usecase]] |
| `NebulaInputPort` / `NebulaOutputPort` | marker protocols : `Sendable` | derived | this note / [[nebula-usecase]] |
| `NebulaRepository<Element>` | `protocol : Sendable` (primary associated type `Element`) | `any NebulaRepository<E>` is `Sendable` when `Element: Sendable` (compiler-verified) | [[nebula-repository]] |
| `NebulaReadOnlyRepository<Element>` | protocol refines `NebulaRepository<Element>` | inherited | [[nebula-repository]] |
| `NebulaWritableRepository<Entity>` | protocol refines `NebulaRepository<Entity> where Entity: NebulaEntity` | inherited | [[nebula-repository]] |
| `NebulaDeletableRepository<Entity>` | capability protocol (opt-in) | inherited | [[nebula-repository]] |
| `NebulaRepositoryError` (+ open `Kind`) | `struct : Sendable, Error` (open-struct `Kind`, reuses `NebulaError.Box`) | derived; NO `@unchecked` | [[nebula-repository]], [[nebula-domain-error]] |
| `NebulaFailure` / `NebulaDomainError` / `NebulaValidationError` | `protocol : Error, Sendable` + per-layer open structs | derived; bridge to closed `NebulaError.Kind` via caller-picked `toNebulaError(kind:)` | [[nebula-domain-error]], [[nebula-error-taxonomy-toolkit]] |
| `NebulaGateway` | marker protocol : `Sendable` | derived | [[nebula-repository]] |
| `NebulaGatewayConfiguration` / `NebulaGatewayConfig` | 5th config struct (`Sendable`, `.with*`) + `Mutex` accessor | derived; `Mutex` is `let` | [[nebula-repository]] |
| `NebulaHTTPGateway` | optional `struct : Sendable` helper (URLSession) | derived (URLSession held in `let`, freeze discipline) | [[nebula-repository]] |
| `NebulaValidator` / `NebulaAsyncValidator` / `NebulaInvariant` | validation seam (Sendable) | derived | [[nebula-validation-invariants]] |
| `NebulaRegistry` / `NebulaRegistryKey` / `NebulaRegistryConfig` | lightweight `Mutex`-backed factory wiring (**NOT a DI container**) | `Mutex` is `let`; `@Sendable` factories | [[nebula-registry-di]] |
| `NebulaFakeRepository` / `NebulaStubUseCase` / `NebulaSpyUseCase` / `NebulaMockRepository` | test doubles (Sendable structs / in-memory) | derived | [[nebula-test-doubles]] |
| `NebulaResultPipeline` / `AsyncSequence` `nebula*` helpers / cancellation helper | async-flow ergonomics | derived / non-escaping `rethrows` | [[nebula-async-flow]] |

> **Deliberate non-recommendations** (the toolkit deliberately does NOT ship these): `AnyUseCase<I, O>` type-erasure box (the protocol-witness generic struct avoids it — [[nebula-usecase]]); a `[Middleware]` array on `NebulaUseCase` (a higher-order `decorate(_:)` decorator is preferred — [[nebula-usecase]]); hand-written `AnyRepository<E>` (`any NebulaRepository<E>` existentials + PATs make it unnecessary — [[nebula-repository]]); new `NebulaError.Kind` cases (bridge via caller-picked kind — [[nebula-domain-error]]).

## Sendable strategy (per type family)

- **Markers / DTOs / IDs / Errors**: derived `Sendable` (all-value, Sendable fields). No `@unchecked` on any Nebula-defined value type (CLAUDE.md binding; `NebulaError.Box` at `Sources/Nebula/Errors/NebulaError.swift:95` is the derived-Sendable `final class` precedent for breaking struct recursion only).
- **Use cases**: `Sendable struct` (stateless, ports in `let`) — derived. `@Sendable` body closure. NOT `Equatable` (the `@Sendable` closure is not `Equatable` — mirrors `NebulaErrorConfiguration` at `Sources/Nebula/Errors/NebulaErrorConfiguration.swift:47`, documented Sendable-only-NOT-Equatable at `:6`/`:35`).
- **Repositories / Gateways (concrete)**: `actor` (DB/external-backed shared state) or `Sendable struct` (in-memory/test). The protocols are `: Sendable`; `any NebulaRepository<E>: Sendable` compiles clean under Swift 6 strict mode when `Element: Sendable` (compiler-verified in the research pass — no `@unchecked` on a Nebula type).
- **Composition / Registry**: `Mutex`-backed, always declared `let` (`Mutex` is `~Copyable` + `@_staticExclusiveOnly` — [[nebula-swift6-concurrency]]). `@Sendable` factory closures; resolved instances must be `Sendable`.
- **Configs**: `Sendable` struct + `@Sendable` handler + fluent `.with*` + process-wide `Mutex<T>` accessor `get()`/`set(_:)` — mirrors `NebulaErrorConfig` (`Sources/Nebula/Errors/NebulaErrorConfig.swift:23` `static let current = Mutex<…>(.default)`, `:26` `get()`, `:31` `set(_:)`). The `Mutex` is `let`.

## DI without a DI framework

`Package.swift:28` `dependencies: []` + `:32` `dependencies: []` forbids Resolver/Factory/Swinject and reactive frameworks (CLAUDE.md "no third-party dependencies"). `DECISIONS.md` row 27 (2026-07-18) decides **both** paths: "Process-wide `Mutex<Nebula*Config>` accessor + explicit-parameter DI (both)" — `NebulaErrorConfig.get()/set(_:)` (Mutex-backed) for ergonomics; explicit `NebulaErrorConfiguration` parameter for testability. The toolkit's wiring helper ([[nebula-registry-di]]) is a `Mutex`-backed registry of port→`@Sendable () -> Any` factory bindings with a generic `resolve(_:as:)` accessor — **deliberately NOT a DI container** (no scoping, no resolution graph, no lifecycle). Primary path = explicit-parameter constructor injection (testable); the registry is the ergonomic seam at the app boundary only. Scope creep into container behavior is a flagged risk ([[clean-architecture-toolkit-risks]]).

## Typed throws (SE-0413)

Public toolkit APIs use untyped `throws` (evolution safety; `DECISIONS.md` row 18). `NebulaError` is the opt-in concrete `Sendable: Error` `Failure` for `throws(NebulaError)` / `Result<T, NebulaError>` (`Sources/Nebula/Errors/NebulaError.swift` doc comment). Per-layer concrete structs (`NebulaDomainError`, `NebulaRepositoryError`, `NebulaValidationError`) are legal typed `Failure`s for module-internal `throws(LayerError)` ([[nebula-domain-error]]). Errors crossing actor boundaries (use case → presenter port, repository → use case) MUST be `Sendable` → bridge to `NebulaError` (`any Error` is not `Sendable`, `DECISIONS.md` row 21), never leak `any Error`. `NebulaError.wrap(_:)` (`Sources/Nebula/Errors/NebulaError+Mapping.swift:158`) is the lossless sync bridge to `Result<T, NebulaError>`; note it is **sync only** (`() throws -> T`) — the async path needs its own `do/catch` reusing the same `as NebulaError` / `NebulaError(error:)` mapping ([[nebula-async-flow]]).

## Dependency-rule enforcement (the hard problem)

Single SPM target ⇒ `internal` access cannot enforce inward-only across files. Nebula encodes the rule **by protocol ownership**: ports/markers defined in Nebula (inner), concrete adapters in the app (outer). Real compile-time enforcement requires the **app** to put entities/use-cases in a separate SPM module that depends on Nebula while adapters depend on that module — Nebula documents the template but cannot mandate it. → [[clean-architecture-toolkit-risks]], [[clean-architecture-open-questions]].

## Out of scope

Presentation patterns (MVVM/MVC/VIP/VIPER). `NebulaOutputPort` is the seam a presenter implements, but Nebula defines **no** presenter/view/viewmodel types. Cosmos owns UI.

## Sources

- Uncle Bob, [The Clean Architecture](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html) (dependency rule, DIP, output port/presenter, DTO boundary data — verbatim-verified).
- Martin Fowler, [Repository](https://martinfowler.com/eaaCatalog/repository.html), [Gateway](https://martinfowler.com/eaaCatalog/gateway.html) (verbatim-verified).
- Root docs: `ARCHITECTURE.md:5` (foundation/architecture), `DECISIONS.md` rows 14/18/19/21/27, `CLAUDE.md`, `Package.swift:28/32` (`dependencies: []`).
- Nebula source: `Sources/Nebula/Errors/NebulaError.swift:55/57/95/97/100`, `NebulaErrorConfiguration.swift:6/17/35/47/53/91`, `NebulaErrorConfig.swift:23/26/31`, `NebulaError+Mapping.swift:158/161/164`, `NebulaLogCategory.swift:21/28/30` (open-struct precedent), `NebulaJSONDecoderConfiguration.swift:36-38` (derived-Sendable wrapper precedent).
- Sibling notes: [[nebula-clean-architecture]] (layer primer), [[nebula-error-taxonomy-toolkit]] (error dimension), [[nebula-swift6-concurrency]] (Mutex/Atomic/sending ground truth), [[nebula-spm-architecture]] (single-target manifest).

Source of truth = root docs (CLAUDE.md, ARCHITECTURE.md, DECISIONS.md, VERSIONING.md); this note is the synthesis. On conflict, the root doc wins.
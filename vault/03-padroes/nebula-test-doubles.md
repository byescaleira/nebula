---
tags: [padroes, architecture, testing, test-doubles, swift-testing, swift6, nebula]
aliases: [NebulaFakeRepository, NebulaStubUseCase, NebulaSpyUseCase, NebulaMockRepository, nebula-test-doubles, Nebula test doubles]
related: [[nebula-clean-architecture-toolkit]], [[nebula-usecase]], [[nebula-repository]], [[nebula-registry-di]], [[nebula-domain-error]], [[nebula-async-flow]], [[nebula-errors]], [[nebula-swift6-concurrency]], [[nebula-clean-architecture-tdd]]
status: shipped
shipped: "0.2.0"
---

# Nebula Test Doubles

The test-double surface for the toolkit: `NebulaFakeRepository` / `NebulaStubUseCase` / `NebulaSpyUseCase` (`NebulaMockRepository` deferred) — the Fake and Spy are `final class` + `let Mutex` (derived `Sendable`, no `@unchecked`), the Stub is a `Sendable` struct; all conformed to the toolkit ports and asserted with Swift Testing. Source of truth = root docs (`ROADMAP.md`, `ARCHITECTURE.md`, the shipped `Sources/Nebula/Architecture/Testing/`); this note is synthesis. On conflict, the root doc/code wins. Part of [[nebula-clean-architecture-toolkit]]; the TDD workflow is [[nebula-clean-architecture-tdd]].

## Framework: Swift Testing (NebulaTests)

`CLAUDE.md`: tests in `NebulaTests` (Swift Testing, no UI snapshots, no ViewInspector — Nebula has no UI). Ground truth — `Testing.swiftmodule` (arm64e-apple-macos, Xcode 27 Beta 3 SDK, developer framework):

- `@Suite` `:1367-1368`, `@Test` `:1372-1386` (peer-attached macros; `@Test` parameterized over `Sendable` collections `:1378-1386`).
- `#expect(_ condition: Bool)` `:657`; `#require(_ condition:)` `:658`, `#require(_ optional:) -> T` `:659`.
- Typed-throws assertions: `#expect(throws: errorType:)` sync `:663` / async `:665`; `#require(throws: errorType:)` sync `:667` / async `:669`; `#require(throws: Never.Type)` `:670`. Backing `__checkClosureCall`: async `throws errorType` `:103` and `throws error: E` (Equatable) `:107` — both take `() async throws -> sending some Any` with `isolation: isolated (any Actor)? = #isolation`. So `throws(NebulaError)` / `throws(NebulaDomainError)` / `throws(NebulaRepositoryError)` use cases/repos are directly assertable. The Equatable-error form (`throws error: E`) requires `E: Equatable` — `NebulaError` is `Hashable` (⇒ `Equatable`); layer error structs should be `Equatable` if specific-instance assertion is wanted.
- `Confirmation : Sendable` `:732`; `confirmation(expectedCount:)` `:738-745` (async, `sending R` + `isolation:`) — for asserting a use case invoked a port N times. `Issue : Sendable` `:746`.

## Test-double taxonomy (Meszaros xUnit patterns, mapped)

| Double | Behavior | Toolkit type | Mutable state? |
|---|---|---|---|
| **Fake** | a working, in-memory implementation of the port (e.g. a `[ID: Entity]` store) | `NebulaFakeRepository<Entity>` | yes — store |
| **Stub** | returns canned answers / throws a canned error | `NebulaStubUseCase<I, O>` | no (config-only) |
| **Spy** | records calls (inputs, count) for later assertion | `NebulaSpyUseCase<I, O>` | yes — record log |
| **Mock** | stub + spy + pre-programmed expectations | `NebulaMockRepository<Entity>` | yes — record + expectations |

## Recommended surface (shipped)

The earlier research draft leaned `actor` for fakes/mocks and a `Sendable struct` for the spy. The **shipped** design (0.2.0) chose `final class` + `let Mutex` for the Fake **and** the Spy, and a `Sendable` struct for the Stub. Rationale: a `Sendable struct` holding a `let Mutex` becomes `~Copyable` (`Mutex` is `~Copyable` + `@_staticExclusiveOnly`), so it cannot be copied — awkward for a double passed around a test. `actor` works but forces every read through `await`, which fights the `find(id:) -> Entity?` / `count() -> Int` sync-shaped requirements. A `final class` with all-`let` `Sendable` stored properties **derives `Sendable`** (compiler-synthesized, no `@unchecked`) and is a plain reference — copyable, sync-readable, no `~Copyable` trap. This mirrors the `NebulaError.Box` derived-Sendable-`final class` precedent, NOT the `NebulaMemoryLogHandler` `@unchecked` exception.

```swift
// Fake — in-memory working repository. final class + let Mutex (derived Sendable, no @unchecked,
// copyable, sync-shaped requirements). Conforms to NebulaKeyedRepository/NebulaWritableRepository/
// NebulaDeletableRepository.
public final class NebulaFakeRepository<Entity: NebulaEntity & Sendable>: NebulaKeyedRepository,
    NebulaWritableRepository, NebulaDeletableRepository {
    public typealias Element = Entity
    private let storage = Mutex<[Entity.ID: Entity]>([:])    // let — Mutex is ~Copyable; class absorbs it
    public func find(id: Entity.ID) async -> Entity? { storage.withLock { $0[id] } }
    public func save(_ entity: Entity) async throws { storage.withLock { $0[entity.id] = entity } }
    public func delete(_ id: Entity.ID) async throws { _ = storage.withLock { $0.removeValue(forKey: id) } }
    public func count() async -> Int { storage.withLock { $0.count } }
    public func stream() -> AsyncThrowingStream<Entity, any Error> { /* AsyncThrowingStream.makeStream */ }
}

// Stub — canned Output or canned error. Sendable struct (no mutable state).
public struct NebulaStubUseCase<I: Sendable, O: Sendable>: Sendable {
    public let output: Result<O, NebulaError>               // NebulaError is Sendable — never any Error
    public init(output: Result<O, NebulaError>) { self.output = output }
    public func execute(_ input: I) async throws -> O { try output.get() }
    public func executeTyped(_ input: I) async throws(NebulaError) -> O { try output.get() }
}

// Spy — records inputs, delegates to a body. final class + let Mutex (derived Sendable — the spy is
// explicitly `: Sendable` so it can be shared across tasks).
public final class NebulaSpyUseCase<I: Sendable, O: Sendable>: Sendable {
    public let body: @Sendable (I) async throws -> O
    private let invocations = Mutex<[I]>([])                 // let
    public init(body: @Sendable @escaping (I) async throws -> O) { self.body = body }
    public var callCount: Int { invocations.withLock { $0.count } }
    public func inputs() -> [I] { invocations.withLock { $0 } }
    public func execute(_ input: I) async throws -> O { invocations.withLock { $0.append(input) }; return try await body(input) }
}

// Mock (NebulaMockRepository) — DEFERRED from 0.2.0 (ROADMAP → Later). When it lands, same
// final class + let Mutex shape: canned store + recorded calls + expected counts.
```

## Sendable strategy (no `@unchecked` on Nebula-defined types)

- **Fakes / Spies with a mutable store**: `final class` + `let Mutex` — derived `Sendable` (a `final class` with all-`let` `Sendable` stored properties synthesizes `Sendable`; `Mutex` is `Sendable` when its value is), no `@unchecked`, copyable, sync-readable. The `let` keeps the `Mutex` reference immutable; mutation happens inside `withLock`. `withLock` uses `sending` (SE-0430). This is the **shipped** shape.
- **Stubs (canned, no state)**: `Sendable struct` — derived `Sendable` (all fields Sendable). The canned `Error` must be `Sendable` → store a `Result<O, NebulaError>` or a layer error (`NebulaDomainError`/`NebulaRepositoryError`), **never** `any Error` (not `Sendable` — `DECISIONS.md` row 21).
- **Why not `actor`?** An `actor` derives `Sendable` too, but it forces `await` on every read, which fights the sync-shaped `find(id:) -> Entity?` / `count() -> Int` requirements and serializes unrelated reads. `actor` remains a fine choice for a double whose port is already fully async, or where strict serial access is desired — it is not the shipped shape.
- **Why not a `Sendable struct` + `let Mutex` for the spy/fake?** The `Mutex` is `~Copyable`, so the struct becomes `~Copyable` and cannot be copied — a double passed into a test harness that copies it will not compile. A `final class` absorbs the `~Copyable` `Mutex` behind a reference (the class itself is copyable). This was the deciding factor.
- **`NebulaMemoryLogHandler` precedent** (`DECISIONS.md` row 25): `public final class NebulaMemoryLogHandler: @unchecked Sendable` is the ONE existing `@unchecked`-on-a-Nebula-type exception, for a test/preview-only `Mutex`-backed ring buffer. The toolkit doubles do NOT follow it — they derive `Sendable` with no `@unchecked` (the `final class` + all-`let`-`Sendable`-properties shape is the `NebulaError.Box` precedent, not the `NebulaMemoryLogHandler` one). Reserve `@unchecked` for a `final class` test helper that genuinely cannot derive `Sendable` (e.g. conforming to a non-`Sendable` protocol) — and document with an inline `// @unchecked because:` comment.

## Wiring: explicit-parameter injection (NOT the registry)

Test doubles are injected via **explicit-parameter constructor injection** ([[nebula-registry-di]] primary path) — never via `NebulaRegistryConfig`. A use case holds its ports in `let`s; the test passes a `NebulaFakeRepository`/`NebulaStubUseCase`/`NebulaSpyUseCase` directly. `NebulaRegistryConfig` is the app-boundary seam only; it is never on the test path. This is the "both paths" decision (`DECISIONS.md` row 27) — explicit param for testability.

## Asserting with Swift Testing

- **Canned error**: `#expect(throws: NebulaError.self) { try await stub.execute(input) }` (async `:665`) — or `#require(throws: specificError)` (`:669`) when the layer error is `Equatable`.
- **Spy call count**: `await confirmation(expectedCount: 3) { confirm in /* drive the use case, call confirm() per invocation */ }` (`:738`); or assert `#expect(spy.recordedInputs().count == 3)` (`:657`).
- **Fake state**: `#expect(try await fake.find(id: x) == saved)` — `NebulaEntity` is NOT `Equatable` by default ([[nebula-validation-invariants]]); compare via `isSameIdentity(as:)` for identity, or make the test entity `Equatable` by hand for snapshot comparison.
- **Typed-throws layer errors**: `#expect(throws: NebulaRepositoryError.self) { try await mock.save(entity) }` (async, `NebulaRepositoryError: Error`); specific-instance form requires `NebulaRepositoryError: Equatable` — make layer error structs `Equatable` if specific-instance assertion is wanted.

## Risks (see [[clean-architecture-toolkit-risks]])

- **`@unchecked` temptation for recorded state** — a `final class` double with a `Mutex` might reach for `@unchecked Sendable` like `NebulaMemoryLogHandler`. The shipped doubles avoid this: `final class` + all-`let` `Sendable` properties **derives** `Sendable` (no `@unchecked`). Reserve `@unchecked` for the documented `NebulaMemoryLogHandler`-style exception (row 25).
- **Canned `any Error` is not `Sendable`** — a stub storing `Result<O, any Error>` will not compile under Swift 6. Store `Result<O, NebulaError>` or a layer error; the shipped `NebulaStubUseCase` uses `Result<O, NebulaError>`.
- **`NebulaEntity` not `Equatable`** complicates fake-state snapshot assertions — compare via `isSameIdentity(as:)` or hand-write `Equatable` on the test entity.
- **`~Copyable` propagation** — the deciding reason the spy/fake are `final class` not `Sendable struct`: a struct holding a `let Mutex<[I]>` becomes `~Copyable` and cannot be copied, which surprises a test that passes the double around. The `final class` absorbs the `~Copyable` `Mutex` behind a copyable reference. (An `actor` would also avoid this, at the cost of forcing `await` on every read.)
- **Mock-vs-Fake blur** — a `NebulaMockRepository` that grows a real in-memory store becomes a `NebulaFakeRepository` + expectations. Keep mocks to stub + spy + expectations; reach for a fake when a working implementation is simpler.

## Open questions (see [[clean-architecture-open-questions]])

- Test-doubles location: ship in the main `Nebula` target (like `NebulaMemoryLogHandler`, row 25) or in a `NebulaTestSupport` target? Binding mandates a single `Nebula` + `NebulaTests` target → lean main target, documented test/preview-only (the `NebulaMemoryLogHandler` precedent).
- Should doubles be generic structs (`NebulaStubUseCase<I, O>`) or conform to a `NebulaInputPort` marker so they store uniformly? The use-case generic struct ([[nebula-usecase]]) resists `any Port` storage; lean generic structs with explicit injection.
- Ship all four (Fake/Stub/Spy/Mock) in v1, or just Fake + Stub (Spy/Mock add recorded-state complexity)? Lean: Fake + Stub + Spy in v1; Mock deferred unless a real seam appears.
- Should doubles bridge thrown errors to `NebulaError` automatically, or throw layer errors raw for typed-throws tests? Lean: throw raw layer errors (typed-throws tests want the concrete type); bridge at the boundary only.

## Sources

- `Testing.swiftmodule` (arm64e-apple-macos, Xcode 27 Beta 3): `@Suite` `:1367-1368`, `@Test` `:1372-1386`, `#expect` `:657`, `#require` `:658-661`, `#expect(throws:)` `:663/665`, `#require(throws:)` `:667/669`, `__checkClosureCall` `:101/103/105/107` (sync/async, errorType/error, `sending some Any` + `isolation:`), `Confirmation :732`, `confirmation(...)` `:738-745`, `Issue :746`.
- `DECISIONS.md` row 25 (`NebulaMemoryLogHandler` `@unchecked Sendable` test/preview-only precedent), row 27 (explicit-param DI for testability), row 21 (`any Error` not Sendable).
- Nebula source: `NebulaError.swift` (`Hashable`⇒`Equatable`), `NebulaErrorConfig.swift:23/26/31` (`Mutex` `let` accessor).
- Sibling notes: [[nebula-usecase]] (`executeTyped` + `#expect(throws: NebulaError.self)`), [[nebula-repository]] (port shapes for fakes/mocks), [[nebula-validation-invariants]] (`NebulaEntity` not `Equatable`), [[nebula-swift6-concurrency]] (`Mutex` `let`/`sending`/`~Copyable`), [[nebula-clean-architecture-tdd]] (TDD workflow).

Source of truth = root docs (CLAUDE.md, ARCHITECTURE.md, DECISIONS.md, VERSIONING.md); this note is the synthesis. On conflict, the root doc wins.
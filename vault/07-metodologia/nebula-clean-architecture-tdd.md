---
tags: [metodologia, tdd, clean-architecture, swift-testing, nebula]
aliases: [Nebula Clean Architecture TDD, Nebula TDD workflow, nebula-clean-architecture-tdd]
related: [[nebula-clean-architecture-toolkit]], [[nebula-usecase]], [[nebula-repository]], [[nebula-validation-invariants]], [[nebula-test-doubles]], [[nebula-domain-error]], [[nebula-registry-di]], [[nebula-async-flow]]
status: shipped
shipped: "0.2.0"
---

# Nebula Clean Architecture TDD Workflow

A Red-Green-Refactor workflow for building a Clean Architecture feature with the Nebula toolkit, driven by Swift Testing. The toolkit's seams (inner-owned ports + DTO marker + Sendable value types + explicit-parameter DI) make the layers independently testable: a use case is tested against a `NebulaFakeRepository`/`NebulaStubUseCase`, never the real adapter. Source of truth = root docs; this note is synthesis. On conflict, the root doc wins. Toolkit surface: [[nebula-clean-architecture-toolkit]]; test doubles: [[nebula-test-doubles]].

## Framework: Swift Testing (NebulaTests)

`CLAUDE.md`: tests in `NebulaTests` (Swift Testing, no UI snapshots, no ViewInspector — Nebula has no UI). Ground truth — `Testing.swiftmodule` (arm64e-apple-macos, Xcode 27 Beta 3): `@Suite` `:1367-1368`, `@Test` `:1372-1386` (parameterized over `Sendable` collections `:1378-1386`), `#expect` `:657`, `#require` `:658-661`, `#expect(throws: errorType:)` sync `:663` / async `:665`, `#require(throws: errorType:)` sync `:667` / async `:669`, `__checkClosureCall` async `:103`/`:107` (`sending some Any` + `isolation: isolated (any Actor)? = #isolation`), `Confirmation :732`, `confirmation(...)` `:738-745`, `Issue :746`. No `XCTestCase`/`setUp`/`tearDown` — Swift Testing uses `@Suite` `struct`s + `@Test` `func`s; init/deinit is the setup/teardown equivalent.

## The workflow (outside-in: port → use case → adapter)

### 1. Red — write a failing use-case test against a fake port

Name the use case's `Input`/`Output` DTOs (Sendable value structs; `Output` may be the `NebulaEntity` itself). Write the test against a `NebulaFakeRepository` ([[nebula-test-doubles]]) — the port does not exist yet, so the test does not compile (Red).

```swift
@Suite struct CreateUserUseCaseTests {
    @Test func createsUserWithGeneratedID() async throws {
        let repo = NebulaFakeRepository<User>()              // fake port (actor, in-memory)
        let useCase = NebulaUseCase<CreateUserInput, User>(
            name: "user.create", role: .command,
            body: { input in try await repo.save(User(id: NebulaID(UUID()), name: input.name)); /* return */ }
        )
        let user = try await useCase.execute(.init(name: "Ada"))
        #expect(try await repo.count() == 1)                 // :657
        #expect(user.name == "Ada")
    }

    @Test func rejectsBlankName() async throws {
        let repo = NebulaFakeRepository<User>()
        let useCase = /* … validates via NebulaValidator … */
        #expect(throws: NebulaValidationError.self) { try await useCase.execute(.init(name: "")) }  // async :665
    }
}
```

### 2. Define the domain (`NebulaEntity` / `NebulaAggregate` / `NebulaID`)

`User: NebulaAggregate` with `let id: NebulaID<User>` and `let name: String` (or a `NebulaValue`-conforming `UserName` wrapping struct with a failable `init` — parse-don't-validate, [[nebula-validation-invariants]]). `NebulaEntity` reuses stdlib `Identifiable` (`Swift.swiftmodule:12443-12446`) and adds `ID: Sendable`; it is deliberately **not** `Equatable` (synthesized `Equatable` is an entity footgun) — compare via `isSameIdentity(as:)`.

### 3. Green — implement the use case + fake to pass

Extract the port: `protocol UserRepository: NebulaWritableRepository<User> {}` (conforms to `NebulaWritableRepository` — [[nebula-repository]]). `NebulaFakeRepository<User>` conforms. The use case holds the port in a `let` (explicit-parameter constructor injection — [[nebula-registry-di]] primary path). Apply cross-cutting concerns via decorators: `useCase.reported().measured().logged()` or the one-call `.instrumented()` ([[nebula-usecase]]). Re-run: Green.

### 4. Test the validation seam

Synchronous rules via `NebulaValidator<T>` / `NebulaValue` failable inits; async rules (uniqueness) via `NebulaAsyncValidator<T>` querying a `NebulaReadOnlyRepository` ([[nebula-validation-invariants]]). Assert typed-throws layer errors: `#expect(throws: NebulaValidationError.self) { … }` (async `:665`); specific-instance form requires the layer error to be `Equatable`.

### 5. Implement the real adapter (app, outside Nebula)

The concrete `CoreDataUserRepository` / `URLSessionUserGateway` lives in the app (Frameworks & Drivers). It conforms to `UserRepository` (`: Sendable`, `actor`-backed for DB shared state). It maps framework errors → `NebulaRepositoryError` → `NebulaError` via `NebulaError(repositoryError:kind:)` (caller-picked coarse `Kind`, [[nebula-repository]]). This layer is **not** Nebula's concern; Nebula tests stop at the port.

### 6. Wire at the composition root (app launch)

Populate `NebulaRegistryConfig.set(…)` with port→factory bindings once at launch; resolve concrete adapters to inject into use cases ([[nebula-registry-di]]). Tests never touch `NebulaRegistryConfig` — they inject fakes directly. Optionally assert wiring with a `confirmation(expectedCount:)` that each port resolves ([[nebula-test-doubles]]).

## Test per layer (what to assert where)

| Layer | Test against | Assert with |
|---|---|---|
| Entity / Value / Aggregate | pure value structs | `#expect(value == …)` (value objects `Equatable`); `#expect(entity.isSameIdentity(as:))` (entities not `Equatable`); failable-init `#expect(throws: NebulaValidationError.self)` for invalid construction |
| Use Case | `NebulaFakeRepository` / `NebulaStubUseCase` (explicit injection) | `#expect`/`#require` on `Output`; `#expect(throws: NebulaDomainError.self)` / `throws(NebulaError)` via `executeTyped`; `confirmation` for port call counts |
| Repository port | `NebulaFakeRepository` (in-memory) | `#expect(try await fake.find(id:) == …)`; `#expect(throws: NebulaRepositoryError.self)` |
| Adapter (app) | real framework (integration test, app-owned) | out of Nebula scope |

## Sendable discipline in tests

- Test doubles are `Sendable` (`actor` for fakes/mocks with a store; `Sendable struct` for stubs; `Mutex`-`let`-struct for spies) — [[nebula-test-doubles]]. No `@unchecked` on Nebula-defined doubles (the `NebulaMemoryLogHandler` `@unchecked` precedent, `DECISIONS.md` row 25, is the one test-helper exception).
- `@Test` parameterized collections require `C: Sendable, C.Element: Sendable` (`:1378-1386`) — test arguments are `Sendable`.
- Async `@Test`/`#expect(throws:)` bodies carry `isolation: isolated (any Actor)? = #isolation` (`:103`/`:107`) — tests run in their own isolation; no `@MainActor` assumed.
- Canned errors in stubs must be `Sendable` → `Result<O, NebulaError>` or a layer error, never `any Error` (`DECISIONS.md` row 21).

## Anti-patterns to avoid

- **Testing use cases against the real adapter** — couples the use-case test to DB/network; defeats the port seam. Always inject a fake/stub.
- **`NebulaRegistryConfig` on the test path** — the registry is the app-boundary seam only; tests inject explicitly (row 27 "both paths" — explicit param for testability).
- **Synthesized `Equatable` on an entity for snapshot tests** — a footgun ([[nebula-validation-invariants]]); use `isSameIdentity(as:)` or hand-write `Equatable` on the test entity.
- **`XCTestCase` + `setUp`/`tearDown`** — Swift Testing uses `@Suite` `struct` init/deinit; mixing frameworks is unnecessary.
- **UI snapshots / ViewInspector** — out of scope (Nebula has no UI; `CLAUDE.md`).

## Risks (see [[clean-architecture-toolkit-risks]])

- **Adapter integration tests are app-owned** — Nebula's TDD workflow stops at the port; an app that skips adapter integration tests has a green Nebula suite but a broken app. Document that adapter tests are the app's responsibility.
- **`executeTyped` lossiness** ([[nebula-usecase]]) — a use case throwing a non-`NebulaError` loses the original's full shape; `#expect(throws: NebulaError.self)` passes but the test may not assert the original. Mitigation: throw/`#expect(throws:)` layer errors (`NebulaDomainError`/`NebulaRepositoryError`) for specific-failure tests; bridge to `NebulaError` only at the boundary.
- **Test-double `~Copyable` propagation** — a spy `Sendable struct` holding a `Mutex<[I]>` `let` is `~Copyable`; a test that copies the spy will not compile. Prefer `actor` spies unless value semantics are needed ([[nebula-test-doubles]]).

## Sources

- `Testing.swiftmodule` (arm64e-apple-macos, Xcode 27 Beta 3): `@Suite` `:1367-1368`, `@Test` `:1372-1386`, `#expect` `:657`, `#require` `:658-661`, `#expect(throws:)` `:663/665`, `#require(throws:)` `:667/669`, `__checkClosureCall` `:103/107`, `Confirmation :732`, `confirmation(...)` `:738-745`, `Issue :746`.
- `Swift.swiftmodule`: `Identifiable<ID>` `:12443-12446`.
- `DECISIONS.md` rows 21 (`any Error` not Sendable), 25 (`NebulaMemoryLogHandler` test-helper precedent), 27 (explicit-param DI for testability).
- Sibling notes: [[nebula-clean-architecture-toolkit]], [[nebula-usecase]], [[nebula-repository]], [[nebula-validation-invariants]], [[nebula-test-doubles]], [[nebula-domain-error]], [[nebula-registry-di]], [[nebula-async-flow]].

Source of truth = root docs (CLAUDE.md, ARCHITECTURE.md, DECISIONS.md, VERSIONING.md); this note is the synthesis. On conflict, the root doc wins.
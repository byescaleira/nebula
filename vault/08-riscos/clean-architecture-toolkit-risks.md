---
tags: [riscos, clean-architecture, architecture, toolkit, swift6, nebula]
aliases: [Clean Architecture Toolkit Risks, nebula-architecture-risks, toolkit risks]
related: [[nebula-clean-architecture-toolkit]], [[nebula-usecase]], [[nebula-repository]], [[nebula-domain-error]], [[nebula-validation-invariants]], [[nebula-registry-di]], [[nebula-test-doubles]], [[nebula-async-flow]], [[nebula-clean-architecture-tdd]], [[clean-architecture-open-questions]]
status: shipped
shipped: "0.2.0"
---

# Clean Architecture Toolkit — Risks

Consolidated open risks for the Nebula Clean Architecture toolkit, gathered from the research/verify dimensions and the synthesis notes. Most-severe first. Source of truth = root docs; this note is synthesis. On conflict, the root doc wins. Surface: [[nebula-clean-architecture-toolkit]]; open design questions: [[clean-architecture-open-questions]].

## 1. Completeness — task-listed types NOT in the toolkit surface (gaps)

The full 12 verified dimensions (ca-theory, usecase, repository, domain-modeling, validation, errors, concurrency, di, tdd, test-doubles, async-flow, boundaries) are synthesized across the 11 notes. The completeness check cross-references each of the 27 task-listed types against its backing dimension. **20 are backed by ≥1 dimension and shipped in the toolkit surface**; **7 are gaps** — intentionally NOT shipped, or shaped differently from the task's expected name:

| Task-listed type | Status | Backing |
|---|---|---|
| `NebulaCommand` | **gap** — modeled as `NebulaUseCaseRole.command`, not a separate type | [[nebula-usecase]], [[clean-architecture-open-questions]] Q2 |
| `NebulaQuery` | **gap** — modeled as `NebulaUseCaseRole.query`, not a separate type | [[nebula-usecase]], [[clean-architecture-open-questions]] Q2 |
| `AnyUseCase<I, O>` | **gap** — intentionally rejected; the protocol-witness generic struct avoids type erasure | [[nebula-clean-architecture-toolkit]] (Deliberate non-recommendations), [[nebula-usecase]] |
| `NebulaUseCaseMiddleware` | **gap** — intentionally rejected; a higher-order `decorate(_:)` decorator is preferred over a `[Middleware]` array | [[nebula-usecase]] |
| `NebulaUseCaseConfig` | **gap** — deferred; decorators route to the EXISTING 3 configs (no 5th config in v1) | [[nebula-usecase]], [[clean-architecture-open-questions]] Q7 |
| `AnyRepository<E>` | **gap** — intentionally rejected; `any NebulaRepository<E>` existentials + PATs make hand-erasure unnecessary | [[nebula-repository]] |
| `NebulaRepositoryError` | **naming gap** — the toolkit names it `NebulaRepositoryError` (no `Nebula` prefix), inconsistent with the `Nebula*` prefix convention used by the sibling `NebulaDomainError`/`NebulaValidationError`; the task-listed `NebulaRepositoryError` is the prefix-conforming name that does NOT exist | [[nebula-repository]], [[nebula-domain-error]] |

The first six are **intentional design decisions** (the toolkit's protocol-witness + decorator + PAT-with-existentials strategy), documented in the canonical surface ([[nebula-clean-architecture-toolkit]] "Deliberate non-recommendations") and the per-dimension notes. The seventh is a **naming inconsistency to resolve before shipping**: either rename `NebulaRepositoryError` → `NebulaRepositoryError` for prefix consistency (mirrors `NebulaDomainError`/`NebulaValidationError`), or document the prefix-drop as a deliberate choice for the repository layer. Recommendation: rename to `NebulaRepositoryError` for consistency with the sibling layer error structs.

## 2. Dependency-rule enforcement is convention, not compile-time

Single SPM target ⇒ `internal` access cannot enforce inward-only across files. Nebula encodes the rule **by protocol ownership** (ports/markers in Nebula-inner; concrete adapters in the app-outer), but a rogue adapter in an inner module compiles fine. Real compile-time enforcement requires the **app** to adopt a multi-module structure (entities/use-cases as a separate product depending on Nebula, adapters depending on that) — Nebula documents the template but cannot mandate it ([[nebula-clean-architecture-toolkit]]). Regression risk if adapters leak into an inner module.

## 3. Composition root → DI container scope creep

A `Mutex`-backed `NebulaRegistry` ([[nebula-registry-di]]) can quietly grow into a DI container (scoping, resolution graphs, lifecycle, auto-injection) — exactly the third-party framework category `dependencies: []` (`Package.swift:28/32`) forbids. Any "just add singleton scope" request re-introduces Resolver/Factory-shaped scope. Mitigation: keep it to factory bindings only; document the boundary loudly; the primary path is explicit-parameter constructor injection (testable), the registry is the app-boundary seam only (`DECISIONS.md` row 27).

## 4. `Sendable` PAT protocols + type-erased registry storage

`Sendable` protocols with `associatedtype`s (`NebulaRepository<Element>`, use-case-style ports) resist `any Port` storage, so a type-erased registry needs `@Sendable () -> Any` + `as? T` casts — a code smell and a dynamic dispatch edge the Swift 6 strict-concurrency checker tolerates but cannot type-prove ([[nebula-registry-di]]). `any NebulaRepository<E>: Sendable` when `Element: Sendable` is compiler-verified (no `@unchecked` on a Nebula type), but the registry's `Any` slot cannot enforce that resolved instances are `Sendable` — document that factories must return `Sendable` values.

## 5. `wrap` is sync-only; async typed-throws needs its own mapping

`NebulaError.wrap(_:)` (`Sources/Nebula/Errors/NebulaError+Mapping.swift:158`) is `(_ body: () throws -> T)` — **no async overload** (verified). So `NebulaUseCase.executeTyped(_:) async throws(NebulaError) -> O` and `NebulaResultPipeline` cannot reuse `wrap` directly; they need their own `do/catch` reusing the same `as NebulaError` (`:161`) / `NebulaError(error:)` (`:164`) mapping, or an async `wrapAsync` ([[nebula-usecase]], [[nebula-async-flow]]). The "no new error-mapping machinery" spirit holds; the "one-liner over `wrap`" claim is imprecise for the async path.

## 6. Bridging arbitrary errors is lossy (recurring surprise)

`any Error` is not `Sendable` (`DECISIONS.md` row 21); mapping inits consume the source error at construction time and keep only `Sendable` fragments. `NebulaRepositoryError`/`NebulaDomainError` bridge to `NebulaError` via caller-picked coarse `Kind` (`DECISIONS.md` row 31 — closed `Kind` enum, no new cases) and the original `any Error` is dropped. `executeTyped` on a body throwing a non-`NebulaError` loses the original's full shape (only `NebulaError` survives) — the existing contract, surfaced at every layer boundary. Must be re-documented on the architecture surface ([[nebula-domain-error]], [[nebula-repository]], [[nebula-usecase]]).

## 7. `NebulaError.init(error:)` dispatch order

If `NebulaError.init(error:)` gains a `NebulaFailure` dispatch branch (so `NebulaError.wrap { try useCase() }` works when the use-case throws a layer error), the `NebulaFailure` branch MUST come before the `NSError` fallback or a layer error is flattened to `NSCocoaErrorDomain`/`.unknown` ([[nebula-domain-error]], [[nebula-error-taxonomy-toolkit]]).

## 8. Markers are documentation, not compile-time enforcement

`NebulaValue` / `NebulaEntity` / `NebulaAggregate` / `NebulaDTO` / `NebulaInputPort` / `NebulaOutputPort` are marker protocols with no required members — a conforming struct can still be mutable, hold non-Sendable fields, or violate invariants. The toolkit cannot literally "GUARANTEE Clean Architecture" from a marker; the guarantee is limited to what the refined protocols (`Sendable`/`Equatable`/`Hashable`/`Identifiable`) already prove ([[nebula-validation-invariants]]). State this honestly.

## 9. Synthesized `Equatable` on an entity is a footgun

Synthesized `Equatable` compares all stored fields (SE-0185) — two snapshots of the same identity at different lifecycle moments compare *unequal*. `NebulaEntity` is deliberately **not** `Equatable`; identity equality is opt-in `isSameIdentity(as:)`. But the type system cannot forbid a user adding `: Equatable` to a `NebulaEntity` struct — the non-`Equatable` default is the strongest signal available ([[nebula-validation-invariants]]). The `NebulaError.Box` hand-written `==` (`Sources/Nebula/Errors/NebulaError.swift:100`) is the precedent for hand-writing `==` where synthesis semantics would differ.

## 10. Actor-boundary chafe for synchronous DB stacks

`Sendable` repository protocols with async-throwing accessors push every concrete repo toward `actor`. Apps with synchronous CoreData/SQLite stacks (or existing non-Sendable ORM layers) may chafe at the actor boundary and incur hop overhead; a sync sub-protocol may be needed ([[nebula-repository]]).

## 11. `NebulaOutputPort` scope creep into presentation

`NebulaOutputPort` is the seam a presenter implements, but Nebula defining ANY shape there risks dragging in presentation concerns (the explicitly-out-of-scope MVVM/MVC/VIP/VIPER). Keeping it a bare marker protocol (no presenter/view/viewmodel types authored in Nebula) is essential to stay in scope ([[nebula-clean-architecture-toolkit]]).

## 12. Decorator ordering hazard

`.instrumented()` composes `reported().measured().logged()` in a fixed order (timing wraps the logged+reported inner body). A user calling `.logged().measured()` manually gets different timing semantics (logging outside vs inside the signpost interval). Mitigation: document loudly; `.instrumented()` exists precisely to own the canonical order ([[nebula-usecase]]).

## 13. `StaticString` name friction

`NebulaUseCase` requires `name: StaticString` so `.measured(_:)` can forward it literally to `OSSignposter.withIntervalSignpost` (`os.OSSignposter` carries `@_semantics("constant_evaluable")` — `Sources/Nebula/Logging/NebulaSignposter.swift:8-13`; `NebulaMeasureConfiguration.measure(_:)` forwarding verified `:48-53`). A dynamically-constructed use case (e.g. from a `String` registry key) cannot get a `StaticString` and loses signpost coverage (`.logged`/`.reported` still work). The os overlay `.swiftinterface` was not grep-located here — the `StaticString`-literal constraint is corroborated by the existing compiled `NebulaSignposter`/`NebulaMeasureConfiguration` but should be re-verified against the os overlay interface ([[nebula-usecase]]).

## 14. `@Sendable` body captures are a source-breaking surprise

A use-case body (or async transform) capturing non-Sendable state will not compile under Swift 6 strict mode — desired (Nebula enforces Sendable), but a surprise for consumers used to non-Sendable closures. Captured repositories must be `Sendable` (`actor` or `Mutex`-backed). Mitigation: docc guidance ([[nebula-usecase]], [[nebula-async-flow]]).

## 15. Recursive aggregate `Box` weakens "value types only"

A recursive aggregate needs a `final class Box: Sendable` (`NebulaError.Box` precedent — `Sources/Nebula/Errors/NebulaError.swift:91-99`, derived `Sendable` on a final class with a `Sendable let`, no `@unchecked`). This introduces a reference type inside an otherwise-value aggregate; the `let` makes it immutable (no shared mutable state), but it must be explained as the constrained exception, not a license for general reference-type use ([[nebula-validation-invariants]]).

## 16. `NebulaEntity` migration friction

Existing app types conforming to `Identifiable` with a non-Sendable ID cannot conform to `NebulaEntity` (which adds `ID: Sendable`) without changing their ID. Rare for domain IDs; document ([[nebula-validation-invariants]]).

## 17. Test-double `~Copyable` propagation + `@unchecked` temptation

A spy `Sendable struct` holding a `Mutex<[I]>` `let` is `~Copyable` (`Mutex` is `~Copyable` + `@_staticExclusiveOnly` — [[nebula-swift6-concurrency]]); a test that copies the spy will not compile. Prefer `actor` for spies. A `final class` double might reach for `@unchecked Sendable` like `NebulaMemoryLogHandler` (`DECISIONS.md` row 25) — reserve `@unchecked` for that one documented test-helper exception; prefer `actor`/`Mutex`-`let`-struct ([[nebula-test-doubles]]).

## 18. `AsyncSequence` helper creep + cancellation is cooperative

The stdlib already has a rich `AsyncSequence` API (`map`/`filter`/`reduce`/`compactMap`/…); shipping wrappers would violate "never redeclare stdlib APIs". Ship only verified gap-fillers (`nebulaChunked`/`nebulaUniqued`), `nebula*`-prefixed ([[nebula-async-flow]]). Cancellation is cooperative — a body that never calls `Task.checkCancellation()` cannot be cancelled mid-flight; the `NebulaCancellation` helper is opt-in, not a preemption.

## 19. Apple API availability re-verify before shipping

The concurrency primitives the surface leans on (`Mutex`/`Atomic`/ordering structs from `Synchronization`; `Clock`/`AsyncStream`/`AsyncThrowingStream` from `_Concurrency`) are all below the `.v26` floor (verified — `_Concurrency.swiftmodule:685/796/1400/1724`, `Synchronization.swiftmodule:9/253/307/360/7839`), so no `@available` gating is needed. But `Mutex.withLock` uses `sending` (SE-0430, NOT `transferring` — `Synchronization.swiftmodule:7855`) — wrapper forwarding signatures must use `sending`. `Identifiable` is `var id: Self.ID { get }` (`Swift.swiftmodule:12443-12446`), `ID : Hashable`; the class-only `id: ObjectIdentifier` extension (`:12447`) is `@available(macOS 10.15, iOS 13.0, …)` — not required by `NebulaEntity`. `OSSignposter` literal-`StaticString` constraint needs an os-overlay interface grep (risk 13). Any `@available` gate MUST include all 5 platforms incl. `visionOS 26` ([[nebula-spm-architecture]]).

## 20. Refuted/uncertain research claims (carry forward)

- **ca-theory claim 6 REFUTED**: the clean-swift citation backs only constructor injection + protocol-based dependency inversion; it does NOT back "Entities as value-type structs" (article uses a class), "UseCases as protocols with execute" (article uses a concrete class), or the "internal is a promise; a separate module is a law" maxim (absent — commonly associated with Point-Free). The Medium citation is paywalled with zero Clean-Architecture content. Attribute community conventions without those citations ([[nebula-clean-architecture]]).
- **repository claim 13 REFUTED** (strong form): CQRS read/write split + async throws is validated across community kits, but "all marked `Sendable` with domain-typed errors" is NOT evidenced — Lambdaspire uses plain untyped `throws`, no `Sendable` markers. `Sendable` + typed errors are Nebula's binding-constraint-driven choices, not community-consistent ([[nebula-repository]]).
- **domain-modeling claim 3 UNCERTAIN**: the aggregate rules (root/local identity, cascade delete, invariant-on-commit, Car/Tire) are real Evans *DDD* ch. 15, but the cited Fowler EvansClassification page contains NO aggregate content — re-cite Evans ch. 15 ([[nebula-validation-invariants]]).
- **repository claim 4 UNCERTAIN**: the Rob Napier "type-erasers = over-engineering" quote is unverifiable (stackoverflow.com blocked); the sentiment aligns with SE-0346 direction but the attribution is not confirmed.
- **usecase claim 6 caveat**: `#expect(throws: specificError)` requires `E: Equatable`; `NebulaError` is `Hashable`⇒`Equatable` so both forms work, but layer error structs must be `Equatable` for specific-instance assertion ([[nebula-test-doubles]]).

## Sources

- Dimension notes: [[nebula-clean-architecture-toolkit]], [[nebula-usecase]], [[nebula-repository]], [[nebula-domain-error]], [[nebula-validation-invariants]], [[nebula-registry-di]], [[nebula-test-doubles]], [[nebula-async-flow]], [[nebula-clean-architecture-tdd]].
- Existing: [[nebula-clean-architecture]], [[nebula-error-taxonomy-toolkit]], [[nebula-errors]], [[nebula-swift6-concurrency]], [[nebula-spm-architecture]].
- Root: `DECISIONS.md` rows 21/25/27/31, `CLAUDE.md`, `Package.swift:28/32`.
- Interface: `_Concurrency.swiftmodule:685/796/1400/1724`, `Synchronization.swiftmodule:9/253/307/360/7839/7855`, `Swift.swiftmodule:12443-12447`, `Testing.swiftmodule:103/107/665/669`.
- Nebula source: `NebulaError.swift:91-100`, `NebulaError+Mapping.swift:158/161/164`, `NebulaSignposter.swift:8-13`, `NebulaMeasureConfiguration.swift:48-53`.

Source of truth = root docs (CLAUDE.md, ARCHITECTURE.md, DECISIONS.md, VERSIONING.md); this note is the synthesis. On conflict, the root doc wins.
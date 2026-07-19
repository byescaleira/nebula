---
tags: [riscos, open-questions, clean-architecture, architecture, toolkit, nebula]
aliases: [Clean Architecture Open Questions, nebula-architecture-open-questions, toolkit design questions]
related: [[clean-architecture-toolkit-risks]], [[nebula-clean-architecture-toolkit]], [[nebula-usecase]], [[nebula-repository]], [[nebula-domain-error]], [[nebula-validation-invariants]], [[nebula-registry-di]], [[nebula-test-doubles]], [[nebula-async-flow]], [[nebula-error-taxonomy-toolkit]]
status: shipped
shipped: "0.2.0"
---

# Clean Architecture Toolkit — Open Design Questions

The ~10 open design questions for the Nebula Clean Architecture toolkit, each with alternatives and a recommendation. Pairs with [[clean-architecture-toolkit-risks]]. Source of truth = root docs; this note is synthesis. On conflict, the root doc wins. Surface: [[nebula-clean-architecture-toolkit]].

> All 12 verified dimensions (ca-theory, usecase, repository, domain-modeling, validation, errors, concurrency, di, tdd, test-doubles, async-flow, boundaries) are synthesized across the 11 notes. Recommendations are grounded in the binding constraints + the dimension findings; ergonomics-level sub-questions (composable validator combinators, registry key shape, double taxonomy, `AsyncSequence` helper set, `NebulaResultPipeline` shape) remain genuinely open.

## ✅ DECISIONS (locked 2026-07-19, discussion w/ user)

All 10 questions resolved. Choices mirror the recommendations unless noted. **No ADR written yet** — this record is vault synthesis; the formal `DECISIONS.md` row is deferred to Wave H implementation kickoff (the user scoped this cycle to research + vault notes only).

| # | Question | Decision |
|---|---|---|
| 1 | Use Case granularity | **Fine-grained** — one `NebulaUseCase<I,O>` per operation, typed `Input`/`Output`; `name: StaticString` at init; ship `executeTyped(_:) async throws(NebulaError) -> O` in v1; placement `Sources/Nebula/Architecture/`. |
| 2 | CQS split | **Closed enum** `NebulaUseCaseRole: String, Sendable { case command, query }` on `NebulaUseCase`; deprecation-runway comment. NOT separate `NebulaCommand`/`NebulaQuery` types. |
| 3 | Error taxonomy | **Per-layer open structs** — `NebulaFailure: Error, Sendable` protocol + `NebulaDomainError`/`NebulaRepositoryError`/`NebulaValidationError`; bridge to closed `NebulaError.Kind` via caller-picked `toNebulaError(kind:)`, NO new `Kind` cases. `NebulaRepositoryError.source` closed enum; fine `code` open `String`. |
| 4 | Repository shape | **Capability sub-protocols** — `NebulaRepository<Element>: Sendable` + `NebulaReadOnlyRepository`/`NebulaWritableRepository<Entity>`/`NebulaDeletableRepository`; NO CRUD mandate; streams return concrete `AsyncThrowingStream`; `ID: Sendable & Hashable` (no new `NebulaValue` marker). |
| 5 | DI scope | **Factories + constructor injection** — `NebulaRegistry` (transient factories, opt-in app-boundary helper) ALONGSIDE explicit-parameter constructor injection as the primary testable path; `NebulaRegistryKey` open struct; both global `NebulaRegistryConfig` and explicit param. |
| 6 | Validator | **Split sync/async** — `NebulaValidator<T>` (sync, pure) + `NebulaAsyncValidator<T>` (async, repo-backed) in v1; DEFER `NebulaInvariant` (aggregate `validateInvariants()`) unless a second use appears. |
| 7 | 5th config | **NOT in v1** — route to existing 3 configs via `.instrumented()` defaults; revisit only if a use-case-specific concern the 3 cannot express appears. |
| 8 | Test-doubles | **Main `Nebula` target**, documented test/preview-only (precedent `NebulaMemoryLogHandler`); ship `NebulaFakeRepository`/`NebulaStubUseCase`/`NebulaSpyUseCase`, DEFER `NebulaMockRepository`. **Shipped shape (0.2.0):** `final class` + `let Mutex` for the Fake and Spy (derived `Sendable`, copyable, sync-readable — a `Mutex`-typed `let` would make a `struct` `~Copyable`/non-copyable), `Sendable struct` for the Stub; **no `@unchecked`** on any Nebula double (derived on a `final class` with all-`let` `Sendable` properties — the `NebulaError.Box` precedent, not the `NebulaMemoryLogHandler` `@unchecked` exception). The earlier `actor` lean was superseded by `final class` to keep the sync-shaped `find(id:)`/`count()` requirements `await`-free. |
| 9 | Cosmos boundary | **Bare `NebulaOutputPort: Sendable` marker** — Nebula owns the seam, app/Cosmos owns the conformance; Nebula defines NO presenter/view/viewmodel. |
| 10 | Compile-time dependency rule | **Nebula single-target + documented `Domain`-module recommendation** — no template product in v1; the compile-time guarantee is the app's to adopt. |

**Cross-cutting (unchanged from DECISIONS row 18):** public toolkit APIs use untyped `throws`; layer errors are opt-in typed `Failure`s for module-internal use.

---

## 1. Use Case granularity

**Question**: one `NebulaUseCase<I, O>` per application operation (fine-grained, typed `Input`/`Output`), or a coarse-grained orchestrator holding multiple bodies?

- **(a) Fine-grained** — one use case = one application rule (Uncle Bob: use cases "contain application specific business rules" and "orchestrate the flow of data to and from the entities"). Each `NebulaUseCase` has a typed `Input`/`Output`; the caller knows the concrete types (so no `AnyUseCase` erasure needed — [[nebula-usecase]]).
- **(b) Coarse-grained orchestrator** — one struct dispatches many operations via an enum/selector.

**Recommendation**: **(a) fine-grained**. Matches Clean Architecture's "one use case per application operation", keeps `Input`/`Output` typed (no erasure), and composes via `.decorate`/`.instrumented` per use case. Coarse orchestrators re-introduce the stringly-typed dispatch seam the toolkit avoids. Sub-questions (provisional): require `name: StaticString` at init (recommend yes — needed for signposting); ship `executeTyped(_:) async throws(NebulaError) -> O` in v1 (recommend yes — opt-in concrete-`Failure` path, directly testable via `#expect(throws: NebulaError.self)` `Testing.swiftmodule:665`); placement `Sources/Nebula/Architecture/` vs `UseCases/` (recommend `Architecture/` — the toolkit grows beyond use cases).

## 2. Command/Query split (CQS)

**Question**: how to model the command/query distinction?

- **(a) Closed `enum NebulaUseCaseRole: String, Sendable { case command, query }`** — CQS is a stable binary, not an extensible taxonomy, so a 2-case closed enum does NOT violate the open-struct-over-closed-enum rule (which scopes to extensible taxonomies like `NebulaError.Kind`, `Sources/Nebula/Errors/NebulaError.swift:57`).
- **(b) Open `struct` with `.command`/`.query` presets** — leaves room for `command(resultful:)` refinements without a library release.
- **(c) Split types `NebulaCommand<I>` / `NebulaQuery<O>`** — separate marker types per role.

**Recommendation**: **(a) closed enum for v1**, with the same deprecation-runway comment `NebulaError.Kind` uses (`:55`). Revisit (b) only if a third role emerges. Reject (c) — splitting into `NebulaCommand`/`NebulaQuery` types duplicates the `NebulaUseCase<I, O>` surface for no compile-time gain (the role is a label, not a type-system constraint). The task-listed `NebulaCommand`/`NebulaQuery` types are therefore **not** recommended as separate types; the `role` enum on `NebulaUseCase` is the canonical CQS marker.

## 3. Error taxonomy shape

**Question**: single `NebulaDomainError` open struct, or `NebulaFailure: Error, Sendable` protocol + per-layer open structs?

- **(a) Single `NebulaDomainError`** — one type, one `toNebulaError(kind:)`. Loses static guarantee that a repository call cannot surface a domain-rule violation; the use-case boundary becomes stringly-typed.
- **(b) `NebulaFailure` protocol + per-layer open structs** (`NebulaDomainError` / `NebulaRepositoryError` / `NebulaValidationError`) — the compiler enforces the layer boundary (a repository cannot `throw NebulaDomainError` without explicit wrapping). Each is a legal typed `Failure` for module-internal `throws(LayerError)`; bridge to the closed `NebulaError.Kind` via caller-picked `toNebulaError(kind:)` — NO new `Kind` cases (`DECISIONS.md` row 31).

**Recommendation**: **(b) per-layer open structs** (rejected (a) — it labels layering without enforcing it). Full rationale in [[nebula-error-taxonomy-toolkit]] and [[nebula-domain-error]]. Sub-questions (provisional): `NebulaRepositoryError.source` closed enum (`local/remote/unknown`) vs open `String` — lean closed for `Source` (fundamental), open `String` for the fine `code`; `coarseKind` default per layer vs always caller-picked — lean default provided, caller override at the boundary.

## 4. Repository shape

**Question**: single CRUD repository protocol, or a base `NebulaRepository<Element>` + CQRS capability sub-protocols?

- **(a) Single CRUD protocol** — `get/save/update/remove` on one protocol. Forces update + delete on every repo; Fowler's Repository has **no `update` verb** and mandates no full CRUD (verified).
- **(b) Base `NebulaRepository<Element>: Sendable` + capability sub-protocols** — `NebulaReadOnlyRepository` (read models, `Element` unconstrained, `stream()`/`count()`/conditional `find(id:)`), `NebulaWritableRepository<Entity> where Entity: NebulaEntity` (`save` add-or-replace, no update), `NebulaDeletableRepository` (opt-in delete). CQRS read/write split validated across community kits.
- **(c) Typed query/specification surface** — Fowler "query specifications" (`NebulaQuery<Entity>`) for v1.

**Recommendation**: **(b) capability protocols, no CRUD mandate**, defer (c) specifications to a later minor. `any NebulaRepository<E>: Sendable` when `Element: Sendable` (compiler-verified — no `@unchecked`); streaming returns concrete `AsyncThrowingStream<Element, any Error>` (`some AsyncSequence` is illegal in a protocol requirement — verified, `_Concurrency.swiftmodule:1402/1453/1460`). Sub-questions (provisional): `NebulaEntity.ID: Sendable & Hashable` sufficient or a new `NebulaValue` marker — lean `Sendable & Hashable`; sync sub-protocol for non-actor DB stacks — defer unless a real chafe appears ([[nebula-repository]]).

## 5. DI scope (registry shape)

**Question**: should `NebulaRegistry` hold factories (transient) or instances (singleton), and should it exist at all?

- **(a) Factories only** — `port → @Sendable () -> Any`, `resolve(_:as:)` invokes per-resolve → transient. Caller wanting singleton caches the resolved instance itself. Keeps the registry out of lifecycle management.
- **(b) Instances** — `port → Sendable` cached, resolve returns the same instance → singleton. Re-introduces lifecycle (the forbidden container category).
- **(c) No registry** — `NebulaRepository`/`NebulaGateway` protocols + explicit constructor injection only; the app wires its own composition root.

**Recommendation**: **(a) factories only**, shipped as an **opt-in** app-boundary helper alongside (c) explicit-parameter constructor injection as the primary testable path (`DECISIONS.md` row 27 "both paths"). Reject (b) — singleton caching is DI-container scope creep ([[nebula-registry-di]]). Sub-questions (provisional): `NebulaRegistryKey` open struct (`Sendable, Hashable, ExpressibleByStringLiteral` — mirrors `NebulaLogCategory`, `Sources/Nebula/Logging/NebulaLogCategory.swift:28`) vs keyed-by-type — lean open struct; single global `NebulaRegistryConfig` vs explicit `NebulaRegistryConfiguration` parameter — lean both (mirror row 27).

## 6. Sync/async validator

**Question**: one validator type, or split `NebulaValidator` (sync, pure) / `NebulaAsyncValidator` (async, repo-backed)? And where does the async variant live?

- **(a) One `NebulaValidator<T>`** — sync only; async rules (uniqueness) handled ad-hoc by the use case.
- **(b) Split `NebulaValidator<T>` + `NebulaAsyncValidator<T>`** — sync for pure rules (parse-don't-validate on `NebulaValue`, range/pattern checks), async for I/O rules (uniqueness against a `NebulaReadOnlyRepository`). The async variant is `@Sendable (T) async throws(NebulaValidationError) -> Void`.
- **(c) Fold both into `NebulaInvariant`** on `NebulaAggregate` (`validateInvariants() async throws`).

**Recommendation**: **(b) split sync/async** — pure rules should not pay an `async` hop, and I/O rules cannot be sync. The validation surface ([[nebula-validation-invariants]]) owns both contracts; the async-flow surface ([[nebula-async-flow]]) owns the `AsyncSequence`/cancellation ergonomics they may use. Lean: ship `NebulaValidator` + `NebulaAsyncValidator` in v1; defer `NebulaInvariant` (aggregate-level `validateInvariants() throws(NebulaError)`) unless it earns a second use — it pulls `NebulaError` into the aggregate contract (a deliberate coupling decision). Open ergonomics (composable rule combinators, error-accumulating vs short-circuit, struct-vs-closure) are tracked in [[nebula-validation-invariants]].

## 7. `NebulaUseCaseConfig` as a 5th process-wide config

**Question**: introduce a 5th `Mutex`-backed config (`NebulaUseCaseConfig`) carrying use-case cross-cutting defaults (log/measure/error configs), or route to the existing 3 configs?

- **(a) 5th config `NebulaUseCaseConfig`** — symmetry with the 4 existing configs (`NebulaLogConfig`/`NebulaErrorConfig`/`NebulaStandardsConfig`/`NebulaMeasureConfig`, `DECISIONS.md` row 27); one place to override all use-case defaults.
- **(b) Route to existing configs** — `.instrumented(using: measure, log, error)` defaults each to `NebulaMeasureConfig.get()`/`NebulaLogConfig.get()`/`NebulaErrorConfig.get()`; no new config. The 4 configs already cover the concerns; a 5th bundles them.

**Recommendation**: **(b) do NOT introduce a 5th config in v1** — route to the existing 3 via `.instrumented()` defaults. A 5th config duplicates the log/measure/error config references in a new struct and adds a `Mutex` accessor for no new concern; it would exist only for symmetry. Revisit only if a use-case-specific concern (e.g. a default `NebulaUseCaseRole`-aware sampling policy) appears that the 3 configs cannot express. ([[nebula-usecase]])

## 8. Test-doubles location

**Question**: ship test doubles in the main `Nebula` target, or a separate `NebulaTestSupport` target?

- **(a) Main `Nebula` target** — the `NebulaMemoryLogHandler` precedent (`DECISIONS.md` row 25: `public final class NebulaMemoryLogHandler: @unchecked Sendable` in `Logging/`, documented test/preview-only). Avoids a sub-product (the single-target rule, row 8).
- **(b) Separate `NebulaTestSupport` target** — cleaner separation, but violates the single-`Nebula` + `NebulaTests` target mandate (`CLAUDE.md`; `Package.swift` products/targets).

**Recommendation (shipped in 0.2.0)**: **(a) main `Nebula` target**, documented test/preview-only (the `NebulaMemoryLogHandler` precedent). Ship `NebulaFakeRepository`/`NebulaStubUseCase`/`NebulaSpyUseCase` (defer `NebulaMockRepository` unless a real seam appears). Sendable discipline (shipped): `final class` + `let Mutex` for fakes/spies with a store (derived `Sendable`, copyable, sync-readable — avoids the `~Copyable` propagation a `Mutex`-`let`-struct would suffer), `Sendable struct` for stubs; **no `@unchecked`** on any Nebula-defined double (derived on a `final class` with all-`let` `Sendable` properties — the `NebulaError.Box` precedent, NOT the `NebulaMemoryLogHandler` `@unchecked` exception; reserve `@unchecked` for a `final class` helper that genuinely cannot derive `Sendable`). The earlier `actor`-for-fakes lean was superseded by `final class` so the sync-shaped `find(id:)`/`count()` requirements stay `await`-free. ([[nebula-test-doubles]])

## 9. Cosmos boundary (presentation seam)

**Question**: where does Nebula end and Cosmos (the SwiftUI design system) / the app begin? Should Nebula define a `NebulaPresenting` sub-protocol shape on `NebulaOutputPort`?

- **(a) Bare `NebulaOutputPort: Sendable` marker** — Nebula defines only the port; the app/Cosmos defines presenter/output-port protocols per use case (success/failure methods taking DTO + `NebulaError`). Nebula defines **no** presenter/view/viewmodel — presentation patterns (MVVM/MVC/VIP/VIPER) are explicitly out of scope.
- **(b) `NebulaPresenting` sub-protocol** — Nebula standardizes the presenter seam (success/failure methods), risking dragging presentation concerns into a foundation library.

**Recommendation**: **(a) bare `NebulaOutputPort` marker** — Nebula owns the seam, Cosmos/app owns the conformance. Nebula is a foundation/architecture library; it presents nothing (`ARCHITECTURE.md:5`; `CLAUDE.md`). Defining any presenter shape risks the out-of-scope presentation patterns. The `NebulaOutputPort`'s output methods take `NebulaDTO`/`NebulaEntity` Sendable values and `NebulaError` for failures; the app/Cosmos supplies the presenter conformance. ([[nebula-clean-architecture-toolkit]])

## 10. Compile-time dependency-rule enforcement (multi-module template)

**Question**: ship a multi-module SPM template (entities + use-cases as a separate product depending on Nebula) for compile-time enforcement, or stay single-target and document the convention?

- **(a) Multi-module template** — `Domain` module (entities/use-cases) depends on `Nebula`; adapters depend on `Domain`. `internal` access then enforces the inward-only rule across modules ("a separate module is a law"). Compile-time guarantee.
- **(b) Single-target + documented convention** — Nebula stays a single target (the binding); the dependency rule is encoded by protocol ownership (ports in Nebula-inner; adapters in app-outer) and documented as a recommended app module structure.

**Recommendation**: **(b) Nebula stays single-target** (the binding mandates a single `Nebula` + `NebulaTests`); **document** a recommended app module structure (a `Domain` module depending on `Nebula` for compile-time enforcement) but do **not** ship a template product in v1. Nebula cannot mandate the consuming app's module structure; it can only recommend it. The compile-time guarantee is the app's to adopt. ([[nebula-clean-architecture-toolkit]], risk 2 in [[clean-architecture-toolkit-risks]]).

## Cross-cutting decision needed

- **Typed-throws-by-default policy**: most public toolkit APIs `throws(NebulaError)` vs untyped `throws` default with `NebulaError` opt-in. `DECISIONS.md` row 18 decides **untyped `throws` default** for public APIs; layer errors are opt-in typed `Failure`s for module-internal use. This holds across questions 1/3/4 — no change recommended.

## Sources

- Dimension notes: [[nebula-usecase]] (Q1/2/7), [[nebula-repository]] (Q4), [[nebula-domain-error]] + [[nebula-error-taxonomy-toolkit]] (Q3), [[nebula-validation-invariants]] (Q6), [[nebula-registry-di]] (Q5), [[nebula-test-doubles]] (Q8), [[nebula-clean-architecture-toolkit]] (Q9/10), [[nebula-async-flow]] (Q6 async ergonomics).
- Root: `DECISIONS.md` rows 8/18/25/27/31, `CLAUDE.md`, `ARCHITECTURE.md:5`.
- Interface: `Testing.swiftmodule:665` (`#expect(throws: errorType:)`), `_Concurrency.swiftmodule:1402/1453/1460` (`AsyncThrowingStream`).
- Nebula source: `NebulaError.swift:55/57`, `NebulaLogCategory.swift:28`.

Source of truth = root docs (CLAUDE.md, ARCHITECTURE.md, DECISIONS.md, VERSIONING.md); this note is the synthesis. On conflict, the root doc wins.
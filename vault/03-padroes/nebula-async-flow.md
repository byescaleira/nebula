---
tags: [padroes, architecture, async, asyncsequence, cancellation, swift6, nebula]
aliases: [NebulaResultPipeline, AsyncSequence nebula helpers, Nebula cancellation, nebula-async-flow, Nebula async flow]
related: [[nebula-clean-architecture-toolkit]], [[nebula-usecase]], [[nebula-repository]], [[nebula-test-doubles]], [[nebula-domain-error]], [[nebula-swift6-concurrency]], [[nebula-collection-extensions]], [[nebula-errors]]
status: shipped
shipped: "0.2.0"
---

# Nebula Async Flow (AsyncSequence helpers, cancellation, result pipeline)

The async-flow ergonomics for the toolkit: `AsyncSequence` `nebula*` gap-filler helpers, a cooperative-cancellation helper, and a `NebulaResultPipeline` for chaining use cases/async operations with `NebulaError` propagation. Source of truth = root docs; this note is synthesis. On conflict, the root doc wins. Part of [[nebula-clean-architecture-toolkit]]; the concurrency primitives ground truth is [[nebula-swift6-concurrency]].

## Ground truth — `_Concurrency` (Xcode 27 Beta 3, arm64e-apple-macos)

- `AsyncSequence<Element, Failure>` `:685` — `public protocol AsyncSequence<Element, Failure>` (PATs; below the `.v26` floor).
- `AsyncStream<Element>` `:796/799`; `@unchecked Sendable where Element: Sendable` `:862` (Apple's `@unchecked`; a Nebula requirement returning it needs no `@unchecked` on a Nebula type).
- `AsyncThrowingStream<Element, Failure> where Failure : Swift::Error` `:1400/1402`; `Continuation: Sendable` `:1404`; `@unchecked Sendable where Element: Sendable` `:1460`; `makeStream` constrained to `Failure == any Swift::Error` `:1453`.
- `Clock<Duration> : Swift::Sendable` `:1724`; `ContinuousClock` `:1764`; `SuspendingClock` `:2730`; async `measure(_:)` `nonisolated(nonsending)` `:1737`.
- `@Sendable` async-throws closure is the canonical Sendable witness form used throughout `_Concurrency` (e.g. `@escaping @Sendable (Self.Element) async -> ElementOfResult?`).

All below the `.v26` floor (iOS 16/macOS 13 for `AsyncStream`/`Clock`; iOS 18/macOS 15 for `Mutex`/`Atomic`) — **no `@available` gating needed** ([[nebula-swift6-concurrency]]).

## `AsyncSequence` `nebula*` helpers (gap-fillers, prefixed)

`CLAUDE.md` mandates the `nebula*` method-label prefix on open `Collection`/`Sequence` ergonomics to avoid stdlib namespace pollution ([[nebula-collection-extensions]]). The same discipline applies to `AsyncSequence` — the prefix avoids colliding with future stdlib `AsyncSequence` additions. **Reuse, don't wrap** stdlib APIs that already exist: `AsyncSequence.map`/`filter`/`reduce`/`compactMap`/`contains`/`allSatisfy`/`first(where:)`/`min`/`max`/`sorted` are stdlib — do NOT redeclare them (CLAUDE.md "never redeclare stdlib APIs"). Nebula ships only the **gap-fillers** the stdlib lacks:

| Helper | Purpose | Stdlib has it? |
|---|---|---|
| `AsyncSequence.nebulaChunked(byCount:)` | non-overlapping async chunks (last may be short) | NO |
| `AsyncSequence.nebulaUniqued(on:)` | first-occurrence dedup over an async stream | NO |
| `AsyncSequence.nebulaCollect(into:)` | eager terminal collect into a Sendable container | `reduce(into:)` exists — prefer stdlib |
| `AsyncSequence.nebulaAdjacentPairs()` | overlapping pair window | NO |
| `AsyncThrowingStream.nebulaFrom(_:)` | wrap a callback-based API into an `AsyncThrowingStream` via `makeStream` | `makeStream` is stdlib `:1453` — prefer stdlib |

Eager terminal helpers use **non-escaping `rethrows`** closures where the closure is synchronous; genuinely async/escaping transforms use `@escaping @Sendable` (the `@Sendable` is required because the transform runs across `await` suspension points — a non-`@Sendable` closure captured across `await` will not compile under Swift 6). No `@unchecked`. No `DispatchQueue`/`NSLock`.

## Cancellation helper (cooperative, caller-owned)

Cancellation is **the caller's `Task` responsibility**, not the use case's — a foundation use case should not impose cancellation semantics on the body ([[nebula-usecase]] open question: "body runs inside the caller's `Task` and inherits its cancellation"). The helper is an **opt-in** ergonomic, not a mandate:

```swift
public enum NebulaCancellation {
    /// Throws `CancellationError` if the current Task is cancelled. A thin, Nebula-prefixed
    /// cooperative-cancellation checkpoint — callers sprinkle it in long-running bodies.
    public static func check() throws { try Task.checkCancellation() }
    /// Wraps a body with a cancellation checkpoint before and after; rethrows the original error.
    @Sendable public static func guarding<I, O>(
        _ body: @Sendable (I) async throws -> O
    ) -> @Sendable (I) async throws -> O {
        { input in try Task.checkCancellation(); let out = try await body(input); try Task.checkCancellation(); return out }
    }
}
```

- `Task.checkCancellation()` / `Task.cancel()` / `Task.isCancelled` are stdlib (`_Concurrency`) — reused, not wrapped. The helper is a thin Nebula-prefixed checkpoint + a higher-order wrapper that composes with `NebulaUseCase.decorate(_:)` ([[nebula-usecase]]).
- `CancellationError` is `Sendable: Error` (stdlib) — it bridges to `NebulaError` via `NebulaError(error:)` (`Sources/Nebula/Errors/NebulaError+Mapping.swift`) like any other error; `NebulaRepositoryError.Kind.cancelled` is a preset for repository-level cancellation surfacing ([[nebula-repository]]).
- **NOT `@MainActor`**: cancellation checkpoints run on any isolation domain; the helper is `@Sendable` and nonisolated.

## `NebulaResultPipeline` — chaining with `NebulaError` propagation

A `Sendable` pipeline that chains use cases / async operations, propagating `Result<T, NebulaError>` so a failure short-circuits the chain. Shape mirrors the closure-witness preference ([[nebula-usecase]]): a generic `Sendable` struct over `@Sendable` closures, NOT a PAT protocol + erasure.

```swift
public struct NebulaResultPipeline<T: Sendable>: Sendable {
    public let run: @Sendable () async -> Result<T, NebulaError>
    public init(run: @escaping @Sendable () async -> Result<T, NebulaError>) { self.run = run }
    public func then<U: Sendable>(_ next: @escaping @Sendable (T) async -> Result<U, NebulaError>)
        -> NebulaResultPipeline<U> {
        NebulaResultPipeline<U> {
            await self.run().flatMapAsync { t in await next(t) }   // Result flatMap with an async body
        }
    }
}
```

- **Sendable**: derived — `T: Sendable`, `run` is `@Sendable`. No `@unchecked`.
- **NOT `Equatable`**: the `@Sendable` closure is not `Equatable` (mirrors `NebulaErrorConfiguration` at `Sources/Nebula/Errors/NebulaErrorConfiguration.swift:47`).
- **Bridges via `NebulaError.wrap`**: `wrap` is **sync only** (`Sources/Nebula/Errors/NebulaError+Mapping.swift:158` — `() throws -> T`, no async overload). The async pipeline needs its own small `do/catch` reusing the same `as NebulaError` (`:161`) / `NebulaError(error:)` (`:164`) mapping, or an async `wrapAsync` helper — the "no new error-mapping machinery" spirit holds, but `wrap` itself does not cover the async path (verified). `Result.flatMap` with an async body is not stdlib; the pipeline implements it inline (`flatMapAsync`).
- Composes with `NebulaUseCase.executeTyped(_:) async throws(NebulaError) -> O` ([[nebula-usecase]]) — a use case's typed-throws execute feeds the pipeline via `Result(catching:)` semantics (SE-0413 made `Result.init(catching:)` lossless for typed throws).

## Sendable strategy

- `AsyncSequence` helpers: lazy wrappers `Sendable` where `Base: Sendable` and the transform closure is `@Sendable` (eager terminal helpers with non-escaping `rethrows` need no `@Sendable`). No `@unchecked`.
- `NebulaCancellation`: pure `@Sendable` functions / wrappers; no state. No `@unchecked`.
- `NebulaResultPipeline<T>`: derived `Sendable` (`T: Sendable`, `@Sendable` `run`). No `@unchecked`. NOT `Equatable`.

## Risks (see [[clean-architecture-toolkit-risks]])

- **`AsyncSequence` helper set creep** — the stdlib already has a rich `AsyncSequence` API; shipping wrappers for `map`/`filter`/`reduce` would violate "never redeclare stdlib APIs". Mitigation: ship only verified gap-fillers (chunked/uniqued/adjacent-pairs); grep `AsyncSequence` extensions before each addition.
- **`@Sendable` on async transforms** is required (cross-`await` capture) — a source-breaking surprise for consumers used to non-`@Sendable` closures. Mitigation: document; eager terminal helpers stay non-escaping `rethrows`.
- **`wrap` is sync-only** — the async pipeline / async typed-throws variants cannot reuse `wrap` directly; they need their own `do/catch` or an async `wrapAsync`. Document loudly to avoid the "one-liner over `wrap`" assumption ([[nebula-usecase]] caveat).
- **Cancellation is cooperative, not enforced** — a body that never calls `Task.checkCancellation()` cannot be cancelled mid-flight; the helper is opt-in. Mitigation: document that `NebulaCancellation.check()` is a checkpoint, not a preemption.
- **`Result.flatMap` with async body is not stdlib** — the pipeline implements `flatMapAsync` inline; a subtle bug there (e.g. not propagating cancellation) would affect every chain. Mitigation: tests + keep `flatMapAsync` tiny.

## Open questions (see [[clean-architecture-open-questions]])

- Sync/async validator: is `NebulaAsyncValidator` (async, repo-backed uniqueness) part of this async-flow surface or the validation surface ([[nebula-validation-invariants]])? Lean: validation surface owns the contract; async-flow owns the `AsyncSequence`/cancellation/pipeline ergonomics.
- Which `AsyncSequence` gap-fillers ship in v1? Recommend `nebulaChunked` + `nebulaUniqued` only; defer `nebulaAdjacentPairs` and any `nebulaCollect` (prefer stdlib `reduce(into:)`).
- Should `NebulaResultPipeline` be a generic struct (above) or compose via `NebulaUseCase.decorate`-style decorators? Lean: generic struct for explicit pipelines; `decorate` for single-use-case cross-cutting.
- Ship an async `NebulaError.wrapAsync(_:)` helper, or leave async typed-throws mapping inline? Lean: ship `wrapAsync` to centralize the `as NebulaError` / `NebulaError(error:)` mapping and avoid divergence.
- Cancellation helper in v1, or defer (caller uses `Task.checkCancellation()` directly)? Lean: defer the wrapper, document the convention; ship only if a second use appears.

## Sources

- `_Concurrency.swiftmodule` (arm64e-apple-macos, Xcode 27 Beta 3): `AsyncSequence` `:685`, `AsyncStream` `:796/799/862`, `AsyncThrowingStream` `:1400/1402/1404/1453/1460`, `Clock` `:1724`, `ContinuousClock` `:1764`, `SuspendingClock` `:2730`, `measure(_:)` `:1737`.
- Nebula source: `NebulaError+Mapping.swift:158/161/164` (`wrap` sync-only, `as NebulaError`, `NebulaError(error:)`), `NebulaErrorConfiguration.swift:47` (Sendable-only-not-Equatable precedent).
- `CLAUDE.md` (`nebula*` prefix on open `Collection`/`Sequence` ergonomics; never redeclare stdlib APIs).
- Sibling notes: [[nebula-swift6-concurrency]] (concurrency ground truth), [[nebula-usecase]] (async execute, cancellation caller-owned, `decorate`), [[nebula-repository]] (`AsyncThrowingStream` concrete return, `NebulaRepositoryError.Kind.cancelled`), [[nebula-collection-extensions]] (`nebula*` prefix discipline), [[nebula-validation-invariants]] (`NebulaAsyncValidator`).

Source of truth = root docs (CLAUDE.md, ARCHITECTURE.md, DECISIONS.md, VERSIONING.md); this note is the synthesis. On conflict, the root doc wins.
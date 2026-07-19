---
tags: [padroes, architecture, usecase, interactor, swift6, nebula]
aliases: [NebulaUseCase, Nebula Use Case, Nebula Interactor, nebula-usecase]
related: [[nebula-clean-architecture-toolkit]], [[nebula-repository]], [[nebula-domain-error]], [[nebula-async-flow]], [[nebula-test-doubles]], [[nebula-errors]], [[nebula-standardize-measure]], [[nebula-logging]], [[nebula-swift6-concurrency]]
status: shipped
shipped: "0.2.0"
---

# Nebula Use Case (`NebulaUseCase<I, O>`)

The application-rules layer of the toolkit: a generic `Sendable` struct over a `@Sendable (I) async throws -> O` body, with a higher-order decorator seam for logging/timing/error-reporting. Deliberately **not** a PAT-based protocol + `AnyUseCase` box. Source of truth = root docs (`ARCHITECTURE.md`, `DECISIONS.md`, `CLAUDE.md`); this note is synthesis. On conflict, the root doc wins. Part of [[nebula-clean-architecture-toolkit]].

## Why a generic struct, not a PAT protocol

A `protocol NebulaUseCase` with `associatedtype Input/Output: Sendable` + `async throws execute` requires an `AnyUseCase<I, O>` type-erasure box for any heterogeneous storage, and `any NebulaUseCase` erases `Input`/`Output` to upper-bound existentials — so `execute()` is **not callable** on the existential without unboxing (SE-0335). Clean-Architecture call sites always know their concrete `Input`/`Output`, so the PAT buys polymorphism nobody needs, at the cost of a permanent erasure surface. The research verify pass confirmed this is sound Swift 6 language behavior.

Instead: a single generic `struct NebulaUseCase<I, O>` holding a `@Sendable` closure — the **protocol-witness / generic-struct** pattern. It eliminates type erasure, composes via `where`-clause extensions, and keeps the closure-as-use-case primitive `@Sendable (I) async throws -> O` as the minimal typed-throws-friendly core (mirrors [SwiftUseCase](https://github.com/xtro/swiftusecase/)'s `AsyncThrowingExecutable<Parameter, Result>` shape, minus that library's PAT + `@Usecase` macro + `AnyUseCase` machinery — verified via WebFetch).

## Recommended surface

```swift
public typealias NebulaUseCaseBody<I, O> = @Sendable (I) async throws -> O
// Constraint enforced at the struct declaration (a typealias cannot carry constraints):
//   where I: Sendable, O: Sendable

public enum NebulaUseCaseRole: String, Sendable { case command, query }

public struct NebulaUseCase<I, O>: Sendable where I: Sendable, O: Sendable {
    public let name: StaticString
    public let role: NebulaUseCaseRole
    public let body: NebulaUseCaseBody<I, O>
    public init(name: StaticString, role: NebulaUseCaseRole = .query,
                body: @escaping NebulaUseCaseBody<I, O>)
    public func execute(_ input: I) async throws -> O          // untyped throws (SE-0413)
    public func executeTyped(_ input: I) async throws(NebulaError) -> O   // opt-in concrete Failure
}
```

- **Sendable**: derived — `name: StaticString`, `role: NebulaUseCaseRole`, `body` (`@Sendable`) are all Sendable. No `@unchecked`.
- **NOT `Equatable`**: the `@Sendable` body closure is not `Equatable` — mirrors `NebulaErrorConfiguration` (`Sources/Nebula/Errors/NebulaErrorConfiguration.swift:47`, documented Sendable-only-NOT-Equatable at `:6`/`:35`).
- **`name: StaticString` is required** (not `String`) so `.measured(_:)` can forward it literally to `OSSignposter.withIntervalSignpost` — see Signposting below. A dynamic `String` cannot synthesize a `StaticString`.
- **`executeTyped`** is a one-liner over the same `as NebulaError` / `NebulaError(error:)` mapping used by `NebulaError.wrap` (`Sources/Nebula/Errors/NebulaError+Mapping.swift:161`/`:164`). IMPORTANT: `wrap` is **sync only** (`() throws -> T` at `:158`, no async overload) — the async `executeTyped` needs its own `do/catch`, not a `wrap` call. Documented lossy for non-`NebulaError` throws (the original `any Error` is dropped, only `NebulaError` survives — `DECISIONS.md` row 21).

## Command/Query (CQS) marker — a legitimate closed enum

`NebulaUseCaseRole` is a closed `enum : String, Sendable { case command, query }`. This does **not** violate the open-struct-over-closed-enum rule: that rule targets **extensible taxonomies** like `NebulaError.Kind` (`Sources/Nebula/Errors/NebulaError.swift:57`, closed with a documented deprecation-runway comment at `:55`). CQS is a **stable binary** with no third case — a 2-case closed `Sendable` enum is consistent with the rule's intent (verified).

## Decorator seam (NOT a middleware array)

A `[Middleware]` array that preserves `I` and `O` through every link is over-constrained — a real middleware wants to transform input or output, which changes the type. The canonical Swift 6 form is a higher-order **decorator** that returns a new `NebulaUseCase<I, O>` (preserving `I`/`O` — the right constraint for cross-cutting concerns that do NOT change the use-case contract):

```swift
extension NebulaUseCase {
    public func decorate(
        _ transform: @Sendable @escaping (I, NebulaUseCaseBody<I, O>) -> NebulaUseCaseBody<I, O>
    ) -> NebulaUseCase<I, O>
}
```

The transform closure is `@Sendable`; the returned struct re-derives `Sendable`. Decorators that change `I` or `O` are a *different* use case (`NebulaUseCase<I', O'>`), not a decorator on this one.

## Convenience decorators (route to EXISTING configs — no 5th config)

The use-case decorators reuse the four existing config structs; **no `NebulaUseCaseConfig` is introduced** (deferred — see [[clean-architecture-open-questions]]):

| Decorator | Routes to | Default | Notes |
|---|---|---|---|
| `.logged(using:)` | `NebulaLogConfiguration.log(_:_:)` (`Sources/Nebula/Logging/NebulaLogConfiguration.swift:34-38`) | `NebulaLogConfig.get()` | Uses the secondary `String` path (defaults `.public`, **loses per-argument redaction** — documented loudly, mirroring the existing `log` caveat); redaction-sensitive callers use `NebulaLogger` with inline `OSLogMessage`. |
| `.measured(using:)` | `NebulaMeasureConfiguration.measure(_:operation:)` (`Sources/Nebula/Measure/NebulaMeasureConfiguration.swift:129+`) | `NebulaMeasureConfig.get()` | Forwards `name: StaticString` literally to `OSSignposter.withIntervalSignpost` (StaticString forwarding verified `:48-53`). |
| `.reported(using:)` | `NebulaErrorConfiguration.report(_:)` (gated on `isEnabled`, `Sources/Nebula/Errors/NebulaErrorConfiguration.swift:91`) | `NebulaErrorConfig.get()` | Catches → maps via `NebulaError(error:)` → reports → **rethrows the original** (reporting is a side-effect, not a transform). A thrown `NebulaError` reported as-is. |
| `.instrumented(using:log:error:)` | composed one-call | each `…Config.get()` | `reported(using: error).measured(using: measure).logged(using: log)` — owns the canonical ordering. |

## No actor isolation leaks

`Clock` is `Sendable` (`_Concurrency.swiftmodule:1724` `public protocol Clock<Duration> : Swift::Sendable`) and the async `measure(_:)` overload is `nonisolated(nonsending)` (`_Concurrency.swiftmodule:1737`) — so a use-case body timed via `NebulaMeasureConfiguration.measure(_:operation:)` inherits **no** actor isolation. `@MainActor` appears in `_Concurrency` only in MainActor-specific helpers (`assumeIsolation`/`Task.detached`), never in `Sendable` protocol witnesses. A use case runs on any actor / nonisolated; the app supplies isolation. No `@MainActor` default (Nebula has none).

## Testability (Swift Testing)

`executeTyped(_:) async throws(NebulaError) -> O` is directly testable with `#expect(throws: NebulaError.self)` — `Testing.swiftmodule:665` `expect<E, R>(throws errorType: E.Type, …)` (async form backing `__checkClosureCall` at `:103` with `sending some Any` + `isolation: isolated (any Actor)? = #isolation`). Caveat (verified): the Equatable-error variant `#expect(throws: specificError)` additionally requires `NebulaError : Equatable` — `NebulaError` is `Hashable` (⇒ `Equatable`) per `Sources/Nebula/Errors/NebulaError.swift`, so **both** the errorType and specific-instance forms are usable. Test doubles ([[nebula-test-doubles]]) build on this seam.

## Signposting requires a literal `StaticString`

`os.OSSignposter` `beginInterval`/`endInterval`/`withIntervalSignpost` carry `@_semantics("constant_evaluable")`, requiring `name` (`StaticString`) and `message` (`SignpostMetadata`) to be **literals at the `OSSignposter` call site** — forwarding a parameter fails ("globalStringTablePointer builtin must be used only on string literals") (`Sources/Nebula/Logging/NebulaSignposter.swift:8-13`). `NebulaMeasureConfiguration.measure(_:)` already forwards a `StaticString` parameter into those call sites and compiles (`:48-53`). Therefore `.measured(_:)` forwards `name: StaticString` literally; a dynamically-constructed use case (e.g. from a `String` registry key) cannot get a `StaticString` and loses signpost coverage but keeps logging/error reporting. Document.

## Risks (see also [[clean-architecture-toolkit-risks]])

- **Heterogeneous storage**: a generic struct cannot store use cases of different `(I, O)` in one collection without a caller-supplied `any Sendable`/enum wrapper. Rare in Clean Architecture (call sites know their types); the PAT would have the same problem. Mitigation: caller wraps in a tagged enum.
- **Decorator ordering hazard**: `.instrumented()` owns the canonical order; a user calling `.logged().measured()` manually gets different timing semantics (logging outside vs inside the signpost interval). Mitigation: document loudly; `.instrumented()` exists precisely to own the order.
- **`StaticString` name friction**: dynamically-named use cases lose signpost coverage (`.logged`/`.reported` still work). Mitigation: document.
- **`@Sendable` body captures**: a body capturing non-Sendable state will not compile under Swift 6 — desired (Nebula enforces Sendable), but a source-breaking surprise. Mitigation: docc guidance; captured repositories must be `Sendable` (`actor` or `Mutex`-backed).
- **`executeTyped` lossiness**: a body throwing a non-`NebulaError` loses the original's full shape (only `NebulaError` survives) — the existing `NebulaError.wrap` contract, surfaced at the use-case boundary. Mitigation: document; consumers needing the original catch before mapping.
- **`OSSignposter` interface re-verify**: the os overlay `.swiftinterface` was not grep-located here; the `StaticString`-literal constraint is corroborated by the existing compiled `NebulaSignposter`/`NebulaMeasureConfiguration`, but should be re-verified against the os overlay interface before shipping.

## Open questions (see [[clean-architecture-open-questions]])

- `name: StaticString` at init (required for signposting) vs accept `String`? Recommend `StaticString`.
- Ship `executeTyped` in v1? Recommend yes — it is the opt-in concrete-`Failure` path; `#expect(throws: NebulaError.self)` tests it directly.
- Should `decorate(_:)` receive `(NebulaUseCase<I,O>, I)` so decorators can read `name`/`role`? Currently `name` is captured by the struct, not threaded into the transform. Needs a call-site ergonomics call.
- Closed `enum NebulaUseCaseRole` vs open struct with presets? Recommend closed enum for v1 (CQS is binary) with the same deprecation-runway comment `NebulaError.Kind` uses.
- Opt-in cancellation policy on `NebulaUseCase` vs caller's `Task`? Recommend **caller's responsibility** — a foundation use case should not impose cancellation semantics; `body` runs inside the caller's `Task` and inherits its cancellation ([[nebula-async-flow]]).
- Placement: `Sources/Nebula/Architecture/` (introducing the architecture sub-layer) vs `Sources/Nebula/UseCases/`? Recommend `Architecture/` — the toolkit grows beyond use cases (`NebulaRepository`, `NebulaMapper<I, O>`).

## Sources

- [SwiftUseCase](https://github.com/xtro/swiftusecase/) — `AsyncThrowingExecutable<Parameter, Result>` + PAT + `AnyUseCase` + `@Usecase` macro (corroborates the erasure cost the generic struct avoids).
- [Protocol witnesses — ioscoachfrank](https://ioscoachfrank.com/protocol-witnesses.html), [June Bash](https://junebash.com/posts/protocol-witnesses/) — generic-struct-over-PAT pattern.
- [WWDC22-110353 — Design protocol interfaces in Swift](https://developer.apple.com/videos/play/wwdc2022/110353/) — associated types in consuming/producing position; `any P` erases PATs.
- `_Concurrency.swiftmodule` (arm64e-apple-macos, Xcode 27 Beta 3): `Clock` `:1724`, async `measure(_:)` `:1737` (`nonisolated(nonsending)`), `AsyncThrowingStream` `:1400`, `AsyncStream` `:796`, `AsyncSequence` `:685`.
- `Testing.swiftmodule`: `#expect(throws: errorType:)` `:665`, `__checkClosureCall` async `:103` (`sending some Any` + `isolation:`).
- Nebula source: `NebulaError.swift:55/57`, `NebulaErrorConfiguration.swift:6/35/47/91`, `NebulaError+Mapping.swift:158/161/164`, `NebulaMeasureConfiguration.swift:48-53/129`, `NebulaSignposter.swift:8-13`, `NebulaLogConfiguration.swift:34-38`, `NebulaErrorConfig.swift`/`NebulaLogConfig.swift`/`NebulaMeasureConfig.swift` (Mutex accessors).
- `DECISIONS.md` rows 18 (typed throws default), 21 (lossy mapping), 27 (Mutex accessor + explicit-param DI).

Source of truth = root docs (CLAUDE.md, ARCHITECTURE.md, DECISIONS.md, VERSIONING.md); this note is the synthesis. On conflict, the root doc wins.
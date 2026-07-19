---
tags: [padroes, architecture, errors, typed-throws, clean-architecture, nebula]
aliases: [NebulaDomainError, Nebula Repository Error, NebulaFailure, nebula-domain-error, Nebula layer errors]
related: [[nebula-clean-architecture-toolkit]], [[nebula-usecase]], [[nebula-repository]], [[nebula-validation-invariants]], [[nebula-error-taxonomy-toolkit]], [[nebula-errors]], [[nebula-swift6-concurrency]]
status: shipped
shipped: "0.2.0"
---

# Nebula Domain / Layer Errors

The architecture-toolkit error dimension: per-layer open structs (`NebulaDomainError` / `NebulaRepositoryError` / `NebulaValidationError`) conforming to a shared `NebulaFailure: Error, Sendable` protocol, **bridging** to the closed `NebulaError.Kind` enum via a **caller-picked** kind — never adding cases. The deeper protocol+structs spec lives in [[nebula-error-taxonomy-toolkit]]; the foundation envelope (`NebulaError`, `Box`, `wrap`, config) lives in [[nebula-errors]]. This note is the synthesis tying the layer errors into the toolkit. Source of truth = root docs; on conflict, the root doc wins. Part of [[nebula-clean-architecture-toolkit]].

## The hard constraint: `NebulaError.Kind` is closed

`Sources/Nebula/Errors/NebulaError.swift:57` — `public enum Kind: String, Sendable, CaseIterable` (network/decoding/encoding/cocoa/file/validation/serialization/unknown). Its own doc (`:55`) names the open-struct deprecation path: "A closed `enum` for v26; the deprecation path to an open `struct` is available if consumers need custom kinds without a library release." `DECISIONS.md` row 31 records the closed-enum-for-v26 decision. The toolkit **MUST NOT** add cases (`.repository`, `.domain`, `.validation` are all forbidden) — adding a case to a typed error enum is source-breaking for exhaustive `catch` under SE-0413, and the binding's open-struct-over-closed-enum rule scopes exactly to extensible taxonomies like this one.

## The bridge: caller-picked coarse `Kind` + open fine `code`

Each layer error is an **open struct** with a fine `code: String` taxonomy and a **bridge** to `NebulaError` that takes the coarse `Kind` as an explicit caller argument:

```swift
public protocol NebulaFailure: Error, Sendable {
    var message: String { get }
    var coarseKind: NebulaError.Kind { get }      // default coarse bucket
    var underlying: NebulaError.Box? { get }       // reuse Sources/Nebula/Errors/NebulaError.swift:95
    var metadata: [String: String] { get }
    static var nebulaDomain: String { get }
    func toNebulaError(kind: NebulaError.Kind) -> NebulaError
}
```

The fine taxonomy lives in each layer struct's open `var code: String` (`"user.notFound"`, `"cache.miss"`, `"required"`). The coarse `Kind` is **caller-picked at the architecture boundary** — e.g. a repository persistence failure bridges as `.cocoa`, a gateway network failure as `.network`, a domain rule violation as `.validation`, default `.unknown`. This is the open-struct-over-closed-enum principle applied at the error dimension.

## The three layer structs

| Layer struct | Thrown by | Coarse `Kind` default | Fine `code` examples |
|---|---|---|---|
| `NebulaDomainError` | use cases (`throws(NebulaDomainError)`) | `.validation` / `.unknown` | `user.notFound`, `auth.unauthorized` |
| `NebulaRepositoryError` | repositories (`throws(NebulaRepositoryError)`) | `.cocoa` / `.network` | `storeFailure`, `notFound`, `alreadyExists`, `mapping` |
| `NebulaValidationError` | validators (`throws(NebulaValidationError)`) | `.validation` | `required`, `outOfRange`, `patternMismatch` |

`NebulaRepositoryError` reuses `NebulaError.Box` (`Sources/Nebula/Errors/NebulaError.swift:95`, derived-Sendable `final class`) for `underlying` — no second box type. See [[nebula-repository]] for its full field set and factory statics.

## Why open structs (not enums) for the layer taxonomies

SE-0413 (implemented Swift 6.0; toolchain Swift 6.3/6.4) makes adding cases to a typed error enum source-breaking for exhaustive `catch`. Clean Architecture layer taxonomies are inherently extensible (new domain rules, new repository sources, new validation rules ship every release). An open `var code: String` plus a closed coarse `Kind` bridge gives extensibility without breaking exhaustive `catch` — and it matches the existing `NebulaError.Kind` deprecation-path direction (open struct as the forward path) and the `NebulaLogCategory` precedent (`Sources/Nebula/Logging/NebulaLogCategory.swift:28`, extensible-by-design comment `:21`). See [[nebula-error-taxonomy-toolkit]] for the full rationale and the rejected single-`NebulaDomainError` alternative (it loses layer enforcement).

## SE-0413 interaction

- Public toolkit APIs use **untyped `throws`** (evolution safety; `DECISIONS.md` row 18). Each layer's concrete struct is a legal typed `Failure` for module-internal `throws(LayerError)`: `func execute() throws(NebulaDomainError)`, `func fetch() throws(NebulaRepositoryError)`. They are `Sendable` (derived) so they cross actors as typed failures.
- `NebulaFailure` (the protocol) is the polymorphic **bridge seam** — `any NebulaFailure` is `Sendable` (protocol refines `Sendable`) but is **NOT** usable as a typed `Failure` (typed throws needs a concrete type). So the protocol is for storage/bridging, not `throws(any NebulaFailure)`.
- At the architecture boundary, bridge to untyped `throws` / `Result<T, NebulaError>` via `toNebulaError(kind:)`. `NebulaError.init(error:)` should gain a `NebulaFailure` dispatch branch **before** the `NSError` fallback so `NebulaError.wrap { try useCase() }` works when the use-case throws a layer error (a `throws(NebulaDomainError)` closure coerces to `() throws -> T`).
- `NebulaError.wrap(_:)` (`Sources/Nebula/Errors/NebulaError+Mapping.swift:158`) is **sync only** (`() throws -> T`) — the async boundary needs its own `do/catch` reusing the same `as NebulaError` / `NebulaError(error:)` mapping ([[nebula-async-flow]]).

## Sendable strategy

All layer structs: derived `Sendable` (all fields Sendable — `String`, `[String:String]`, `NebulaError.Box?`, open `Kind` struct). **No `@unchecked` on any Nebula-defined type.** Errors crossing actor boundaries (repository → use case, use case → presenter port) MUST be `Sendable` → bridge to `NebulaError`; `any Error` is not `Sendable` (`DECISIONS.md` row 21).

## Risks (see [[clean-architecture-toolkit-risks]])

- **`NebulaError.init(error:)` dispatch order**: the `NebulaFailure` branch must come before `NSError` so a layer error is not flattened to `NSCocoaErrorDomain`/`.unknown`.
- **`NebulaFailure` protocol `Self`-referential members** would block `any NebulaFailure` use — keep it to plain `var` getters + one `func` returning `NebulaError` (no `Self`).
- **Bridging is lossy** for the original `any Error` (only `NebulaError` survives) — the existing contract, surfaced at every layer boundary.
- **`NebulaUseCaseError` as a fourth layer**, or fold use-case failures into `NebulaDomainError`? Lean: domain covers use-case output; do not add a fourth unless a real seam appears ([[clean-architecture-open-questions]]).

## Open questions (see [[clean-architecture-open-questions]])

- `NebulaRepositoryError.source` a small closed enum (`local/remote/unknown`) or open `String`? Lean closed for `Source` (fundamental, non-extensible), open `String` for the fine `code`.
- Typed-throws surface per layer (`throws(NebulaDomainError)` etc.) shipped in v1, or untyped-`throws` only with layer structs as opt-in `Failure`s? See error-taxonomy shape question.
- `coarseKind` default per layer, or always caller-picked? Lean: default provided, caller override at the boundary.

## Sources

- `Sources/Nebula/Errors/NebulaError.swift:55/57/95` (closed `Kind`, `Box`).
- `Sources/Nebula/Errors/NebulaError+Mapping.swift:158/161/164` (`wrap`, `as NebulaError`, `NebulaError(error:)`).
- `Sources/Nebula/Logging/NebulaLogCategory.swift:21/28/30` (open-struct precedent).
- `DECISIONS.md` rows 18 (typed throws default), 21 (lossy mapping), 31 (closed `Kind` for v26).
- [SE-0413](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0413-typed-throws.md).
- Sibling notes: [[nebula-error-taxonomy-toolkit]] (protocol + per-layer structs spec), [[nebula-errors]] (foundation envelope), [[nebula-repository]] (`NebulaRepositoryError` fields), [[nebula-validation-invariants]] (`NebulaValidationError`).

Source of truth = root docs (CLAUDE.md, ARCHITECTURE.md, DECISIONS.md, VERSIONING.md); this note is the synthesis. On conflict, the root doc wins.
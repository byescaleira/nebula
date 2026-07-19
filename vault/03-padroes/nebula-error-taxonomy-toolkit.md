---
tags: [padroes, errors, architecture, typed-throws, clean-architecture]
aliases: [Nebula Error Taxonomy, NebulaFailure, Nebula Domain Error, nebula-error-taxonomy]
related: [[nebula-errors], [nebula-swift6-concurrency], [nebula-spm-architecture]]
---

# Nebula Error Taxonomy + Typed Throws (Architecture Toolkit)

Synthesis note for the architecture-toolkit error dimension. Recommends **protocol + per-layer open structs** (`NebulaFailure` + `NebulaDomainError`/`NebulaRepositoryError`/`NebulaValidationError`) bridging to the closed `NebulaError.Kind` enum WITHOUT adding cases. The root docs ([[ARCHITECTURE]], [[DECISIONS]]) and `Sources/Nebula/Errors/NebulaError.swift` are source of truth; this note is synthesis.

## The two options compared

### (a) Single `NebulaDomainError` open struct
One open struct carries a `layer`/`origin` tag plus a `code: String`. Pro: one type to teach, one `toNebulaError(kind:)`. Con: loses static guarantee that a repository call cannot surface a domain-rule violation; the use-case boundary becomes a stringly-typed seam; `throws(NebulaDomainError)` at every layer erases the layer distinction the toolkit is supposed to GUARANTEE. Rejected — it does not enforce Clean Architecture layering, it merely labels it.

### (b) `NebulaFailure` protocol + per-layer open structs (RECOMMENDED)
Each layer gets its own open `struct` conforming to a shared `NebulaFailure: Error, Sendable` protocol. Use-cases declare `throws(NebulaDomainError)`; repositories declare `throws(NebulaRepositoryError)`; validators declare `throws(NebulaValidationError)`. The compiler enforces the layer boundary (a repository cannot throw a `NebulaDomainError` without explicit wrapping). The protocol is the BRIDGE SEAM to the envelope — not the typed failure type itself.

## The bridge to the CLOSED `NebulaError.Kind` enum

`NebulaError.Kind` is a closed `String`-raw enum (`network/decoding/encoding/cocoa/file/validation/serialization/unknown`) — see `Sources/Nebula/Errors/NebulaError.swift` L57-74. Its own doc (L55-56) names the open-struct deprecation path but the toolkit MUST NOT add cases. The bridge is caller-picked and coarse:

```swift
public protocol NebulaFailure: Error, Sendable {
    var message: String { get }
    var coarseKind: NebulaError.Kind { get }      // default coarse bucket
    var underlying: NebulaError.Box? { get }
    var metadata: [String: String] { get }
    static var nebulaDomain: String { get }
    func toNebulaError(kind: NebulaError.Kind) -> NebulaError
}

public extension NebulaFailure {
    static var nebulaDomain: String { "Nebula.Failure" }
    func toNebulaError(kind: NebulaError.Kind) -> NebulaError {
        NebulaError(
            code: NebulaError.Code(domain: Self.nebulaDomain, code: 0),
            kind: kind,                      // caller-picked coarse kind
            message: message,
            metadata: metadata,
            underlying: underlying
        )
    }
    func toNebulaError() -> NebulaError { toNebulaError(kind: coarseKind) }
}
```

Example bridge — caller picks the coarse kind explicitly at the architecture boundary:

```swift
let err = NebulaDomainError(code: "user.notFound", message: "User not found")
let envelope = err.toNebulaError(kind: .validation)   // explicit
let envelope2 = err.toNebulaError()                    // default coarseKind
```

The fine-grained taxonomy lives in each layer struct's OPEN `var code: String` (e.g. `"user.notFound"`, `"cache.miss"`, `"required"`) — never as new `Kind` cases. This is the open-struct-over-closed-enum principle applied at the error dimension.

## SE-0413 (typed throws) interaction

- SE-0413 is implemented in Swift 6.0 (toolchain is Swift 6.3/6.4) — `throws(ConcreteError)` typechecks against SDK 27.
- SE-0413 guidance: untyped `throws` remains the default for PUBLIC APIs; typed throws suits module-internal/constrained code and generic pass-through. Adding cases to a typed error enum is source-breaking for exhaustive `catch` — which is exactly why the layer taxonomies are OPEN STRUCTS (extensible `code: String`), not typed enums.
- Each layer's concrete conforming struct is a legal typed `Failure`: `func execute() throws(NebulaDomainError)`, `func fetch() throws(NebulaRepositoryError)`. They are `Sendable` (derived) so they cross actors as typed failures.
- `NebulaFailure` (the protocol) is the polymorphic bridge seam — `any NebulaFailure` is `Sendable` (protocol refines `Sendable`) but is NOT usable as a typed `Failure` (typed throws needs a concrete type). So the protocol is for storage/bridging, not for `throws(any NebulaFailure)`.
- At the architecture boundary (public Nebula API / app composition root), bridge to untyped `throws` / `Result<T, NebulaError>` via `toNebulaError(kind:)`. `NebulaError.init(error:)` gains a `NebulaFailure` dispatch branch BEFORE the `NSError` fallback so `NebulaError.wrap { try useCase() }` works when the use-case throws a layer error (a `throws(NebulaDomainError)` closure coerces to `() throws -> T`).

## Why open structs (not enums) for the layer taxonomies

SE-0413 makes adding cases to a typed error enum source-breaking. Clean Architecture layer taxonomies are inherently extensible (new domain rules, new repository sources, new validation rules ship every release). An open `var code: String` plus a closed coarse `Kind` bridge gives extensibility without breaking exhaustive `catch`. This mirrors the existing `NebulaError.Kind` deprecation-path comment (open struct as the forward path).

## Open questions / risks

- Should `NebulaRepositoryError.source` be a small closed enum (`local/remote/unknown`) or an open `String`? Closed enum is stable and Sendable-derived; open string is consistent with the open-struct principle. Lean closed for `Source` (fundamental, non-extensible), open `String` for the fine `code`.
- `NebulaUseCaseError` as a fourth layer struct, or fold use-case failures into `NebulaDomainError`? Lean: domain covers use-case output; do not add a fourth unless a real seam appears.
- `NebulaFailure` protocol `Self`-referential members would block `any NebulaFailure` use — keep it to plain `var` getters + one `func` returning `NebulaError` (no `Self`).
- `NebulaError.init(error:)` dispatch ORDER: `NebulaFailure` branch must come before `NSError` so a layer error is not flattened to `NSCocoaErrorDomain`/`.unknown`.

## Sources

- `Sources/Nebula/Errors/NebulaError.swift` (Kind enum L57-74, deprecation-path comment L55-56, `Box` L95-102)
- `Sources/Nebula/Errors/NebulaError+Mapping.swift` (`init(error:)` dispatch L131-149, `wrap` L158-166)
- `Sources/Nebula/Errors/NebulaErrorConfiguration.swift`, `NebulaErrorConfig.swift` (config contract)
- [[nebula-errors]] (SE-0413 + Sendability ground truth)
- [SE-0413](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0413-typed-throws.md)
- [Typed throws error chains (FlineDev/ErrorKit)](https://fline.dev/blog/swift-6-typed-throws-error-chains/)
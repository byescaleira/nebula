---
tags: [foundation, primitive-extensions]
aliases: [nebula-primitives, nebula-bool-uuid-optional]
related: [[nebula-logging], [nebula-errors], [nebula-date-time-extensions], [nebula-string-extensions], [nebula-number-measurement-extensions], [nebula-collection-extensions], [nebula-codable-foundation], [nebula-data-url-extensions], [nebula-standardize-measure], [nebula-spm-architecture], [nebula-swift6-concurrency]]
---

# Nebula Bool, UUID, Optional & Primitive Extensions

This note designs Nebula's primitive extensions: `Bool`, `UUID`, `Optional`, `Int`/`UInt`, `Range`, and `Comparable`. It is the synthesis of ground-truth checks against the installed Foundation `.swiftinterface` (Xcode 27 Beta 3 / MacOSX27.0.sdk, arm64e-apple-macos), Apple developer docs, Swift Evolution proposals, and swift-foundation source. The root docs (CLAUDE.md, ARCHITECTURE.md, DECISIONS.md, VERSIONING.md) win on conflict.

> Verification note: two WebFetch calls on `developer.apple.com/documentation/foundation/uuid` returned hallucinated data (iOS 13+ availability for `random(using:)`, a parameterless `random()`, and "UUID does not conform to Comparable"). Those results were **rejected** in favor of the authoritative `.swiftinterface`, which confirms `random(using:)` is 26.4-gated, no parameterless `random()` exists, and UUID is `Comparable` since iOS 17. The `random(using:)` API originates from swift-foundation SF-0031 (`@available(FoundationPreview 6.3, *)`), surfaced in Apple's SDK as OS 26.4.

## Ground truth: what Foundation/stdlib already provide

### Bool
`Bool.toggle()` is **stdlib** — [SE-0199](https://github.com/apple/swift-evolution/blob/main/proposals/0199-bool-toggle.md) (accepted, Swift 4.2), signature `@inlinable public mutating func toggle()` (body `self = !self`). Apple's [Bool docs](https://developer.apple.com/documentation/swift/bool) confirm `toggle()` is the only mutating convenience; `or(_:)`/`and(_:)`/`then(_:)` do **not** exist — Apple deliberately relies on short-circuiting `||`/`&&`. **Nebula must NOT redeclare `toggle()`** (ambiguity + zero-warnings violation). Recommendation: SKIP `or`/`and`/`then` to stay Apple-aligned.

### UUID
From the Foundation `.swiftinterface` (lines 13912-13951) and Apple's [UUID docs](https://developer.apple.com/documentation/foundation/uuid):
- `public struct UUID : Hashable, Equatable, CustomStringConvertible, Sendable` — `@available(macOS 10.8, iOS 6.0, tvOS 9.0, watchOS 2.0, *)`.
- `init()`, `init(uuid: uuid_t)`, `init?(uuidString: String)`, `var uuid`, `var uuidString`.
- `Comparable` conformance `@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)` (line 13948) — within the `.v26` floor.
- **NEW & above-floor:** `@available(macOS 26.4, iOS 26.4, tvOS 26.4, watchOS 26.4, visionOS 26.4, *) public static func random(using generator: inout some RandomNumberGenerator) -> UUID` (line 13923-13924). This is **Nebula 26.4** (above the `.v26` floor). It originates from [swift-foundation SF-0031](https://github.com/swiftlang/swift-foundation/blob/main/Proposals/0031-random-uuid.md) (FoundationPreview 6.3), surfaced as OS 26.4 in Apple's SDK. Any Nebula use must be gated with `@available(iOS 26.4, *)` (and the other 4 platforms) and version-documented. There is **no parameterless** `random()` — only `random(using:)`. Note `UUID()` already generates a random v4 UUID at all versions, so `random(using:)` is mainly for custom RNGs. A follow-up proposal [SF-0041](https://forums.swift.org/t/review-sf-0041-uuid-version-support-and-other-enhancements/86848) (FoundationPreview 6.4) adds UUID v7 / lowercase / Span access — also above-floor when it lands; out of scope here.

### Optional
`Optional.orThrow`/`or(_:)`/`orDefault`/`isNilOrEmpty` are **not in stdlib**. Repeated pitches ([Throw on nil](https://forums.swift.org/t/throw-on-nil/39970), [Optional.orThrow pitch](https://forums.swift.org/t/pitch-optional-orthrow/69995)) and SE-0217 (`!!`/`?!` operators) were rejected/deferred. The long-term preferred solution is throw-as-expression, which has not landed. Nebula fills the gap. Canonical community reference: [Swift by Sundell — Extending optionals](https://www.swiftbysundell.com/articles/extending-optionals-in-swift). Pitfall: when `Wrapped == Error` the `orThrow(_:)` overloads collide ([Paul Calnan](https://www.paulcalnan.com/archives/2023/4/requiring-optionals.html)) — mitigate with a concrete `NebulaNilError: Error, Sendable`.

### Int / UInt / BinaryInteger / Range / Comparable
Grep of the Foundation `.swiftinterface` confirms Foundation adds **only**:
- `BinaryInteger.formatted()` / `formatted(_:)` — block at line 19374 (no explicit @available on the formatted-only block).
- `BinaryInteger` init/parse via `IntegerFormatStyle`/`ParseStrategy` — `@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)` (lines 19380-19386).
- `Range<BinaryInteger>.init?(_ NSRange)` / `Range<Int>.init?(_ NSRange)` / `Range<String.Index>.init?(_ NSRange, in:)` (lines 22997-23011).

Foundation adds **no** `clamp`/`clamped`/`isEven`/`isOdd`/`times`/`roman` (grep returns zero hits), and there is **zero** `extension Swift::Comparable` in Foundation. `isMultiple(of:)` is stdlib (Swift 5.0) — do NOT redeclare. `clamped(to:)` is **not** in stdlib: [SE-0177](https://github.com/apple/swift-evolution/blob/main/proposals/0177-add-clamped-to-method.md) was **returned for revision** (Core Team asked for `RangeExpression` generality) and [never re-accepted](https://forums.swift.org/t/revisiting-se-0177-adding-clamped-to/38332). This is a real, Apple-acknowledged gap Nebula may fill.

> Stdlib verification caveat: the Swift stdlib ships as a prebuilt binary `.swiftmodule` with no textual `.swiftinterface` in this toolchain (`Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx` has no `Swift.swiftinterface`), so `Bool.toggle()` / `isMultiple(of:)` / `Comparable` were verified via SE proposals + Apple docs + apple/swift stdlib source rather than an interface grep.

## Recommended design for Nebula

### Module placement

`Sources/Nebula/Extensions/Primitives/` (single SPM target `Nebula`, one `import Nebula`):
- `Bool+Nebula.swift`
- `UUID+Nebula.swift`
- `Optional+Nebula.swift`
- `Integer+Nebula.swift`
- `Range+Nebula.swift`
- `Comparable+Nebula.swift`

### Public API surface

| Symbol | Kind | Purpose |
|---|---|---|
| `Comparable.clamped(to: ClosedRange<Self>) -> Self` | method | Fills SE-0177 gap. Sendable by derivation. |
| `Comparable.clamped(to: some RangeExpression) -> Self` | method | Generic overload (Core Team's RangeExpression ask). Handle partial/empty ranges carefully. |
| `BinaryInteger.isEven` / `isOdd` | computed property | Delegate to stdlib `isMultiple(of: 2)`. Do NOT redeclare `isMultiple`. |
| `BinaryInteger.clamped(to: ClosedRange<Self>) -> Self` | method | Integer-specialized clamp. |
| `BinaryInteger.times(_ body: () throws -> Void) rethrows` | method | Run body `self` times. **NON-escaping, NON-@Sendable** `rethrows` (matches stdlib `forEach`). The closure does not escape, so `@Sendable` is wrong — an earlier draft marked it `@Sendable`; corrected. |
| `Optional.or(_ default: @autoclosure () throws -> Wrapped) rethrows -> Wrapped` | method | Safe unwrap with fallback. |
| `Optional.orThrow(_ error: @autoclosure () -> some Error = NebulaNilError()) throws -> Wrapped` | method | Throw on nil. Default `NebulaNilError` to avoid `Wrapped == Error` collision. |
| `Optional.isNilOrEmpty -> Bool` | computed property (where `Wrapped: Collection`) | Sundell pattern, constrained. |
| `NebulaNilError` | `struct: Error, Sendable` | Concrete Sendable nil-unwrap error (mirrors [[nebula-errors]] message-only discipline). |
| `UUID.shortString -> String` | computed property | First 8 hex chars of `uuidString`. |
| `UUID.isValid(_ string: String) -> Bool` | static method | Validate via existing `init?(uuidString:)`. |
| `UUID.nebulaRandom() -> UUID` | static method, `@available(iOS 26.4, macOS 26.4, tvOS 26.4, watchOS 26.4, visionOS 26.4, *)` | Parameterless convenience over `random(using:)` (SF-0031 / FoundationPreview 6.3 → OS 26.4). Nebula 26.4 (above-floor). Open question: may be unnecessary since `UUID()` is the default v4 generator. |
| `Range.clamp(_ value: Bound) -> Bound` | method | Range-side clamp entry point. |
| `Bool (no new methods)` | non-recommendation | `toggle()` is stdlib (SE-0199). Skip `or`/`and`/`then` to stay Apple-aligned. |

### Design rules

- Extensions on `Sendable` value types (Bool, UUID, Int, `Optional<Sendable>`) **derive** `Sendable` — no `@unchecked`, no annotations.
- No mutable global state in this dimension → no `Mutex`/`Atomic` needed (see [[nebula-swift6-concurrency]]).
- No UIKit; Foundation/Swift only; no third-party deps (see [[nebula-spm-architecture]]).
- Gate above-floor: `UUID.random(using:)` is 26.4 across all 5 platforms (`.swiftinterface` line 13923-13924) → `@available(iOS 26.4, *)` on `UUID.nebulaRandom()` and any caller. Flag as Nebula 26.4 (above-floor per VERSIONING.md).
- `@autoclosure` + `rethrows` for `or(_:)`/`orThrow(_:)` — zero-cost, matches stdlib `??`.
- `times` body is **non-escaping, non-`@Sendable`** `rethrows` (matches stdlib `forEach`); only add `@Sendable` if a future variant lets the closure escape.
- DocC on every public symbol; retirement via `@available(*, deprecated, message:)`.
- Top-level introduced symbols carry the `Nebula` prefix (`NebulaNilError`); on-type methods keep natural names (`clamped(to:)`, `or(_:)`).
- Mirror the Cosmos sibling's value-type + `@Sendable`-handler + `.with*` discipline (see `CosmosLogConfiguration.swift`, `CosmosErrorConfiguration.swift`) — but this dimension is stateless, so no configuration struct is needed. If a configurable formatter is wanted later, use the Sendable-struct + `@Sendable`-handler + fluent `.with*` builder WITHOUT SwiftUI `@Entry`/`@Observable` (Nebula is not SwiftUI).

## Apple patterns adopted

- Sendable value-type extensions with **derived** conformance (no `@unchecked`) — mirrors Cosmos contracts and Apple stdlib practice.
- Prefer modern Swift over legacy Cocoa: **no NumberFormatter** (use `ByteCountFormatStyle` where available; **skip roman numerals** — no Apple-native FormatStyle exists; zero `roman` hits in Foundation).
- **Do not shadow stdlib**: respect SE-0199 `toggle()`, stdlib `isMultiple(of:)`, `UUID.init?(uuidString:)`, `UUID.uuidString`. Extend only where Apple has a gap.
- Fill an Apple-acknowledged gap with `clamped(to:)` (SE-0177, returned for revision) — provide the `RangeExpression` generality the Core Team asked for.
- Gate above-floor features with `@available`: `UUID.random(using:)` is 26.4 across all 5 platforms (`.swiftinterface` line 13923-13924; sourced from swift-foundation SF-0031 / FoundationPreview 6.3).
- Concrete `Sendable` error type (`NebulaNilError`) instead of `any Error` — mirrors `CosmosErrorEvent` holding message + code because `any Error` is not `Sendable` (SE-0302); see [[nebula-errors]].
- `@autoclosure` + `rethrows` for `or(_:)`/`orThrow(_:)` — matches stdlib `??` and `orEmpty`.
- No UIKit, no third-party deps, Foundation/Swift only — enforced across all primitive extension files.

## Risks & open questions

### Risks
- `UUID.random(using:)` at `@available(macOS 26.4, iOS 26.4, ...)` is **above the `.v26` floor** — ungated use breaks watchOS/tvOS `.v26` builds. Every Nebula call site needs `if #available(iOS 26.4, *)` or a gated wrapper. (Apple's UUID doc pages hallucinated iOS 13+ availability when fetched — ignore; trust the `.swiftinterface`.)
- Redefining `Bool.toggle()` (SE-0199) or `isMultiple(of:)` (Swift 5.0) causes ambiguity warnings → zero-warnings violation. Grep for collisions before shipping.
- `clamped(to:)` on `Comparable` pollutes API for non-numeric `Comparable`s (`String`, `URL`) — the SE-0177 debate. Mitigate via the constrained `BinaryInteger.clamped(to:)` and document the `Comparable` version's range semantics; consider constraining to `Strideable` if narrower scope is preferred.
- `Optional.orThrow` overload collision when `Wrapped == Error` (Paul Calnan). Mitigate with a single concrete `NebulaNilError` default and a distinct label.
- `Int.roman` has **no Apple-native source** (zero `roman` hits in `IntegerFormatStyle`/Foundation) — building one is gold-plating with locale/correctness risk. **Recommend SKIP.**
- `IntegerFormatStyle`/`ByteCountFormatStyle` require iOS 15+ (within floor; verified at line 19380 `@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)`) — any bytes/number formatting helper must use `FormatStyle` (not `NumberFormatter`) and the file carries `@available(iOS 15, *)` where relied upon. Verify nothing leaks above `.v26`.
- `RangeExpression.relative(to:)` needs a lower-bound collection to resolve partial ranges; the generic `clamped(to: some RangeExpression)` overload must handle unbounded/one-sided/empty ranges carefully or crash.
- Extending `Optional` globally with `or(_:)` is visible to all `Optional<Wrapped>` in consumers — surface bloat; document prominently.
- Internal inconsistency caught in verification: the apiSurface marked `times(@Sendable ...)` while the design text said non-`@Sendable`. Corrected to non-`@Sendable` non-escaping `rethrows` (matches stdlib `forEach`); only add `@Sendable` if the closure ever escapes.

### Open questions
- Should `Bool.or(_:)`/`and(_:)`/`then(_:)` be added despite Apple's deliberate omission? Current recommendation: **SKIP** (stay Apple-aligned). Needs user confirmation.
- `clamped(to:)` on `Comparable` (matches SE-0177/community) vs `Strideable` (narrower, avoids String/URL pollution)?
- `Int.roman`: skip (recommended — no Apple-native source) or implement a small locale-independent formatter?
- `Optional.orThrow` default to generic `NebulaNilError` or require an explicit error argument?
- Does `UUID.nebulaRandom()` earn its surface, given `UUID()` already produces a random v4 UUID and `random(using:)` is only useful for custom RNGs? Keep it gated at 26.4 and document `UUID()` as the default generator.
- Subfolder `Primitives/` under `Extensions/`, or flat under `Extensions/`? CLAUDE.md lists `Extensions/` as the top folder; `Primitives/` is a subfolder choice to confirm.
- Configurable formatter struct for primitive formatting (bytes/clamp rounding), or keep extensions stateless? Recommendation: **stateless** for this dimension.
- If Nebula ever back-deploys via swift-foundation (FoundationPreview), the `FoundationPreview 6.3` attribute on `UUID.random(using:)` needs separate handling — but for the `.v26` Apple-platform floor, OS-level `@available(iOS 26.4, *)` gating is correct and sufficient.

## Sources

- [Foundation.UUID — developer.apple.com](https://developer.apple.com/documentation/foundation/uuid) (NOTE: WebFetch on this page returned hallucinated availability/Comparable data — rejected in favor of the `.swiftinterface`)
- [Swift.Bool — developer.apple.com](https://developer.apple.com/documentation/swift/bool)
- [SE-0199: Add toggle to Bool](https://github.com/apple/swift-evolution/blob/main/proposals/0199-bool-toggle.md)
- [apple/swift stdlib/public/core/Bool.swift](https://github.com/apple/swift/blob/main/stdlib/public/core/Bool.swift)
- [SE-0177: Add clamped(to:) to Comparable/Strideable](https://github.com/apple/swift-evolution/blob/main/proposals/0177-add-clamped-to-method.md) (status: returned for revision)
- [Revisiting SE-0177: Adding clamped(to:) — Swift Forums](https://forums.swift.org/t/revisiting-se-0177-adding-clamped-to/38332)
- [swift-foundation SF-0031: Random UUID](https://github.com/swiftlang/swift-foundation/blob/main/Proposals/0031-random-uuid.md) — source of `UUID.random(using:)` (`@available(FoundationPreview 6.3, *)` → OS 26.4)
- [SF-0041: UUID Version Support and Other Enhancements — Swift Forums](https://forums.swift.org/t/review-sf-0041-uuid-version-support-and-other-enhancements/86848)
- [Extending optionals in Swift — Swift by Sundell](https://www.swiftbysundell.com/articles/extending-optionals-in-swift)
- [Pitch: Optional.orThrow — Swift Forums](https://forums.swift.org/t/pitch-optional-orthrow/69995)
- [Throw on nil — Swift Forums](https://forums.swift.org/t/throw-on-nil/39970)
- [Paul Calnan: Requiring Optionals](https://www.paulcalnan.com/archives/2023/4/requiring-optionals.html)
- Foundation.swiftinterface (ground truth): `/Applications/Xcode-27.0.0-Beta.3.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/Foundation.framework/Versions/C/Modules/Foundation.swiftmodule/arm64e-apple-macos.swiftinterface` — UUID lines 13912-13951 (`random(using:)` at 13923-13924; `Comparable` at 13948-13951); BinaryInteger extensions 19374-19386; Range 22997-23011.
- Cosmos sibling pattern: `/Users/rafael.escaleira/Documents/projects/personal/cosmos/Sources/Cosmos/Base/Configuration/CosmosLogConfiguration.swift`, `CosmosErrorConfiguration.swift`.

Source of truth = root docs (CLAUDE.md, ARCHITECTURE.md, DECISIONS.md, VERSIONING.md); this note is the synthesis. On conflict, the root doc wins.
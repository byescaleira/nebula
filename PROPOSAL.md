# Proposal: Nebula

## 1. Problem

Rafael's app foundation concerns — logging, errors, value-type extensions, formatting, and measurement — are scattered and ad hoc across his projects. No Sendable-first, Apple-aligned, Swift-6-clean foundation layer exists in the sibling ecosystem: logging reaches for `swift-log` (a third-party dep), errors carry non-Sendable `any Error` existentials, formatting leans on legacy non-Sendable `Formatter` subclasses, and extensions duplicate logic per project. Starting from the UI (as the Cosmos reset taught) led to inconsistent behavior and duplicate configuration plumbing. A foundation layer that begins with Sendable contracts avoids the same trap at the architecture layer.

## 2. Solution

Create `Nebula`, a foundation/architecture SwiftPM library (sibling of `Cosmos`, the SwiftUI design system) that begins with **Sendable configuration contracts** — `NebulaLogConfiguration`, `NebulaErrorConfiguration`, `NebulaStandards`, `NebulaMeasureConfiguration` — plus a `NebulaError` envelope and extensions on Foundation value types. Every public type is `Sendable`; every handler is `@Sendable`; every contract has fluent `.with*` builders. Nebula wraps only Apple-native primitives: `os.Logger`/`OSSignposter` (not `swift-log`), the `FormatStyle` family (not legacy `Formatter` subclasses), `Measurement`, `Regex`, `AttributedString`, `Duration`/`Clock`, `Mutex`/`Atomic` (not `NSLock`). One `import Nebula`, no third-party dependencies, no SwiftUI.

## 3. Goals

- Predictable logging, error reporting, formatting, and measurement through shared Sendable contracts.
- Apple-native feel aligned with the modern Foundation stack (`FormatStyle`, `Measurement`, `os.Logger`, `Regex`).
- Swift 6 strict concurrency with `Sendable` value types and zero concurrency warnings.
- A single SPM target `Nebula` that exposes logging, errors, extensions, formatting, and measurement through one `import Nebula`.
- Lossy-but-Sendable error mapping that consumes `any Error` at construction time and keeps only Sendable fragments.
- DocC documentation and Apple-aligned `@available` gates (all 5 platforms incl. `visionOS 26`).

## 4. Non-goals

- UIKit support or any explicit UIKit dependency.
- SwiftUI environment integration or any `@Entry`/`@Observable`/`@Environment` surface (apps inject explicitly).
- Pre-v26 Apple platform compatibility (Nebula major == OS major; baseline Nebula 26).
- UI/presentation layer (Nebula reports, it does not present — that's Cosmos's job).
- `RecoverableError` adoption (AppKit-oriented, escaping closure, not multiplatform-Sendable-friendly).
- Back-deployment via `FoundationPreview` in v1 (Apple-platform-only at `.v26`).
- Runtime theming engine (static configurations only).
- Third-party dependencies (`swift-log`, `swift-algorithms`, etc. are explicitly out — implement in-house under a `Nebula` prefix).

## 5. Success Criteria

- `swift build` and `swift test` pass on every commit, on each target platform (iOS/macOS/tvOS/watchOS/visionOS).
- Zero concurrency warnings under Swift 6 mode.
- Every contract is documented and unit-tested.
- Every public type is `Sendable` by derived conformance (no `@unchecked` on Nebula-defined types).
- DocC catalog builds natively in Xcode 26/27.
- Every `@available` gate is re-verified against the Xcode `.swiftinterface` (the #1 historical rework source).

## 6. Risks

| Risk | Mitigation |
|---|---|
| Over-engineering the extension surface | Keep extensions narrowly-targeted; `nebula*` prefix on open Collection/Sequence; skip gold-plating (`Int.roman`, `Bool.or/and/then`, MD5/SHA1). |
| Lossy error mapping drops the original `any Error` | Document loudly; consumers needing the original must catch before mapping. `NebulaError` carries only Sendable fragments. |
| `~Copyable` wrapper propagation through `NebulaLocked`/`NebulaFlag`/`NebulaOnce` | Validate `~Copyable`+`Sendable` synthesis against the exact Swift 6.4 toolchain before scaffolding; hold as `let` globals / inside actors. |
| Above-floor 26.4 APIs (`base64URLAlphabet`, `omitPaddingCharacter`, `ianaName`, `UUID.random(using:)`) | Gate with `@available(iOS 26.4, macOS 26.4, tvOS 26.4, watchOS 26.4, visionOS 26.4, *)`; defer non-essential to Nebula 26.4. |
| `OSMetricOperation` (OS 26 signpost-metrics) is internal to the os overlay | Cannot re-export; if metrics are needed, define a public `NebulaMetricOperation` enum gated `@available(iOS 26, *)`. Defer to Nebula 27. |
| visionOS availability of `OSLogStore.Scope.system`/`.local()` uncertain from headers | Conservatively gate unavailable on visionOS; confirm at compile time on the visionOS SDK. |
| `WebFetch` hallucinated availability tables (UUID.random, percentEncodedQueryItems, OutputFormatting.fragmentsAllowed) | The `.swiftinterface` is authoritative — cite interface line numbers when verifying; never rely on WebFetch for availability. |
| `@available(macOS 12, *)` does NOT make a symbol macOS-only (the `*` fallback enables all platforms) | Use `#if os(macOS)` or explicit per-platform `@available(<platform>, unavailable)` for macOS-only surfaces. |

## 7. Next Steps

1. Waves B–G per `ROADMAP.md` — logging + signposts, errors, extensions batch 1, extensions batch 2, standardize + measure, DocC + CI + polish.
2. Populate the Obsidian vault (`vault/`) with the 10 foundation research notes + 2 pattern notes; link from `[[Home]]`.
3. Re-verify every `@available` clause against the Xcode 27 Beta.3 `.swiftinterface` at each wave's implementation time.
4. Tag `0.1.0` after Wave G (DocC + CI + polish).
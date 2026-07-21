# Nebula — Project Guidelines

Nebula is a Swift foundation/architecture SwiftPM library (sibling of Cosmos, the SwiftUI design system). These guidelines are **binding** for all work in this repository.

## Stack & targets
- Swift **6.3+** toolchain (dual Xcode 26.4+ / Xcode 27 build), **Swift language mode v6**, Xcode 26.4+. NOTE: Xcode 26.0–26.3 shipped Swift 6.2 and will NOT parse a `swift-tools-version: 6.3` manifest — require Xcode 26.4+ for the Swift 6.3 path. OS-27-only SDK symbols are compile-gated with `#if swift(>=6.4)` so they compile to a graceful fallback on Swift 6.3 and turn on under Xcode 27 / Swift 6.4.
- Platforms: **iOS / macOS / tvOS / watchOS / visionOS — all at `.v26`**. Every public type must compile and behave well on all 5.
- Single target `Nebula`, no third-party dependencies. Tests in `NebulaTests` (Swift Testing, no UI snapshots, no ViewInspector — Nebula has no UI).

## No UIKit / no SwiftUI / no SwiftData
Never author UIKit symbols: no `import UIKit`, `UIColor`, `UIViewController`, `UIHostingController`, or `#if canImport(UIKit)`. Never author SwiftUI or SwiftData symbols. Foundation APIs that wrap UIKit internally are not invoked from Nebula. There is no haptics/font/CoreText surface — those are Cosmos concerns.

**Allowed system frameworks (non-UI only):** `Foundation`, `os`, `Synchronization`, `_Concurrency`, `CryptoKit` (behind `NebulaHashAlgorithm`), `Network` (precedent: `NebulaHTTPServer`), `Security` (Keychain `SecItem*` + SSL pinning `SecTrust*`), `BackgroundTasks`, `UserNotifications`, `MetricKit`, `StoreKit`, `CloudKit` (precedent: the N19 observability suite — `CKContainer`/`CKDatabase`/`CKSyncEngine` are clean `Sendable` on all 5 platforms below the `.v26` floor; the `@unchecked` CK value types are Apple classes, NOT Nebula value types, handled by the documented `final class @unchecked` box + copy-to-Sendable at the adapter boundary). The principle: any **non-UI Apple system framework** is admissible if a feature needs it and it can be gated to all 5 platforms (or explicit per-platform `@available(<platform>, unavailable)` for the subset that lacks it). Never UIKit/SwiftUI/SwiftUI-bridged (`TipKit` is `@_exported import SwiftUI` → Cosmos-only). Every platform-restricted surface MUST use explicit per-platform `@available` gates (e.g. `@available(macOS 26, unavailable)` + `@available(watchOS 26, unavailable)`) — **NOT `@available(iOS 13, *)`**, whose `*` fallback enables ALL platforms.

## Foundation contracts — Sendable struct + @Sendable handler + .with* (NO @Entry)
Nebula has **no SwiftUI** — no `@Entry`, no `@Observable`, no `@MainActor` default isolation, no `@Environment`. Cross-cutting concerns flow through four Sendable value-type configuration structs, each with a `@Sendable` handler and fluent `.with*` builders (mirror `CosmosConfiguration`/`CosmosLogConfiguration`/`CosmosErrorConfiguration`, minus the SwiftUI environment plumbing):

- `NebulaLogConfiguration` — log level, category, subsystem, min level, handler. `logger()` builds a `NebulaLogger`; `log(_:_:)` is the String convenience path (defaults `.public`, loses per-argument redaction — document loudly; steer redaction-sensitive callers to `NebulaLogger` with inline `OSLogMessage` interpolation).
- `NebulaErrorConfiguration` — isEnabled, category, handler. `report(_:)` gates on `isEnabled`. **Sendable ONLY — NOT `Equatable`** (the `@Sendable` handler closure is not `Equatable`, mirroring `CosmosErrorConfiguration`).
- `NebulaStandards` — locale/timeZone/calendar + FormatStyle accessors + `.withLocale`/`.withTimeZone`/`.withCalendar`.
- `NebulaMeasureConfiguration` — clock, signposter, enabled, handler.

Each defaults to sensible values (default handler `{ _ in }` capture-free, trivially Sendable). Apps inject explicitly — there is no environment. Two injection paths: (1) process-wide `Mutex<Nebula*Config>` accessor (`NebulaErrorConfig.get()/set(_:)`); (2) explicit-parameter DI for testability. Per-instance overrides use `.with*` builders that return a mutated copy.

## Extensions conventions
Extensions live in `Sources/Nebula/Extensions/{DateTime,String,Number,Primitive,Collection,Codable,DataURL}/`. Rules:
- All extensions on value types derive `Sendable` when the base is `Sendable` — **derive, never author `@unchecked Sendable` on a Nebula-defined type**.
- **No stdlib namespace pollution**: `nebula*` method-label prefix on open `Collection`/`Sequence` ergonomics (`nebulaChunked`, `nebulaUniqued`, `nebulaStablePartition`, `nebulaSorted`) so they never collide with future stdlib additions. Natural names on gap-fillers (`Comparable.clamped(to:)`, `Optional.or(_:)`, `BinaryInteger.isEven`) where the stdlib deliberately lacks the API.
- **Never redeclare stdlib APIs**: `Bool.toggle()` (SE-0199), `BinaryInteger.isMultiple(of:)` (Swift 5.0), `String.firstMatch(of:)`/`wholeMatch(of:)`/`matches(of:)` (iOS 16) — reuse, don't wrap. Grep for collisions before shipping.
- **No legacy `Formatter` subclasses** in the public surface: `NumberFormatter`/`DateFormatter`/`MeasurementFormatter`/`ByteCountFormatter`/`ISO8601DateFormatter` are superseded by the Sendable `FormatStyle` family. The single exception is `ListFormatter` (no FormatStyle replacement, not Sendable) — wrap per-call, never cache.
- Gate above-floor APIs with `@available(iOS 26.4, macOS 26.4, tvOS 26.4, watchOS 26.4, visionOS 26.4, *)` (the 26.4 family: `Data.Base64EncodingOptions.base64URLAlphabet`/`.omitPaddingCharacter`, `String.Encoding.ianaName` getter AND `init?(ianaName:)`, `UUID.random(using:)`).

## Concurrency — Modern Swift 6, zero warnings
The project must build with **zero concurrency warnings** under Swift 6 mode. Fix isolation/Sendable; do not silence.
- All public value types are `Sendable` (derived conformance; avoid `@unchecked`).
- Handler closures in configurations are `@Sendable`. Default `{ _ in }` is capture-free.
- **No `NSLock`, no `DispatchQueue` for synchronization, no `nonisolated(unsafe)` mutable globals.** Shared mutable state uses `Mutex<T>` / `Atomic<T>` from `import Synchronization` (SwiftStdlib 6.0 → iOS 18/macOS 15/tvOS 18/watchOS 11/visionOS 2, below the `.v26` floor so no gating needed).
- **Once-token pattern for idempotent setup**: a `static let` whose initializer side-effect runs exactly once, thread-safely, via `swift_once` (Darwin `dispatch_once_f`). No lock primitive. Side-effect-only form: `private static let _register: Void = { NebulaStandards.bootstrap() }()`. For instance-scoped one-time work, use `NebulaOnce` (body runs outside the lock).
- `Mutex<T>`/`Atomic<T>` are `~Copyable` and `@_staticExclusiveOnly` → always declare `let`, never `var`. A `Mutex`-typed stored property propagates `~Copyable` to the owning type; prefer keeping shared-state containers as standalone `let` globals or inside `actor`-isolated types.
- **Region-based isolation (SE-0414) is the default alternative to `@unchecked`.** Before reaching for `@unchecked Sendable`, restructure so the compiler can prove the non-Sendable transfer is safe.
- **Actors, not global actors.** Nebula has no `@MainActor` default isolation (no SwiftUI). Use `actor` types only when shared mutable state spans many call sites and a single `Mutex` is awkward. An app consuming Nebula supplies its own isolation.
- **Typed throws (SE-0413).** `NebulaError` is a concrete `Sendable: Error` type. Public Nebula APIs use untyped `throws` (evolution safety); `NebulaError` is exposed as an opt-in concrete `Failure` for consumers that declare `throws(NebulaError)` / `Result<T, NebulaError>`. Error types crossing actor boundaries MUST be `Sendable` — derive it.
- **Correct `Atomic` ordering types**: there is NO single `Ordering` enum — three frozen structs: `AtomicLoadOrdering` (`.relaxed`/`.acquiring`/`.sequentiallyConsistent` — `.acquiringAndReleasing` is INVALID for `load`), `AtomicStoreOrdering`, `AtomicUpdateOrdering` (`.acquiringAndReleasing` valid here, used by `compareExchange`/`exchange`). `Mutex.withLock` uses `sending` (SE-0430), NOT `transferring` (the earlier SE-0433 spelling was revised).
- SE-0470 (isolated conformances, Swift 6.2, experimental feature flags) is ABOVE the Nebula 26 floor — do not rely on it; keep all conformances nonisolated.

## Versioning — Nebula N ↔ OS N
- A Nebula major version equals the OS major it targets. **Current baseline: Nebula 26** (OS 26 / Liquid Glass).
- API availability IS Nebula API versioning: "available since Nebula 26" == `@available(iOS 26, *)`. `@available` gates MUST include all 5 platforms: `@available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)`. Centralize `if #available` gates for OS-introduced features.
- Above-floor surfaces: "since Nebula 26.4" == `@available(iOS 26.4, macOS 26.4, tvOS 26.4, watchOS 26.4, visionOS 26.4, *)` (base64URL/omitPadding, ianaName, UUID.random(using:)).
- `macOS-only` gating uses `#if os(macOS)` or explicit per-platform `@available(<platform>, unavailable)` — **NOT `@available(macOS 12, *)` alone**, whose `*` fallback enables ALL platforms. (`NebulaLogStoreExporter.Scope.system` / `.local()` are macOS-only; visionOS availability is uncertain from headers → conservatively gate unavailable.)
- Within a Nebula major: semver minor/patch. Deprecate with `@available(*, deprecated, message:)` + a migration runway before obsoletion. Policy in `VERSIONING.md`; changes in `CHANGELOG.md`.

## Research → Obsidian vault (binding)
**Every research task — competitive analysis, API investigation, docs review, verification — must be persisted into the Obsidian knowledge vault at `vault/`** (open it in Obsidian: *Open folder as vault* → `vault/`). The vault is the project's long-term memory; it is not acceptable to do research and leave it only in chat.

- Write findings as interlinked markdown notes (frontmatter `tags`/`aliases`/`related` + `[[wikilinks]]`; kebab-case filenames). Add to the appropriate folder: `01-fundamentos/` (foundation subsystems), `03-padroes/` (SPM architecture, Swift 6 concurrency), `07-metodologia/` (workflows/methods), `08-riscos/` (open risks/refuted specs), `02-decisoes/` (new ADRs).
- Link from `[[Home]]` (the MOC) and any related notes so the graph stays connected. Verify new `[[wikilinks]]` resolve (alias or filename).
- The **source of truth stays the root docs** (`ARCHITECTURE.md`, `DECISIONS.md`, `VERSIONING.md`, `CLAUDE.md`); the vault is a synthesis/navigation layer. On conflict, the root doc wins — update the note.
- Prefer a focused note over appending to an existing wall of text; cross-link instead of duplicating.
- The `.swiftinterface` (Xcode 27 Beta 3 SDK) is the authoritative ground truth for Apple API availability — not WebFetch (which has hallucinated availability tables for `percentEncodedQueryItems`, `UUID.random()`, `OutputFormatting.fragmentsAllowed`, etc.). Cite interface line numbers when verifying.

## Build & verify
`swift build && swift test && swift build -c release`. Build for **each** target platform to confirm `#if os()` coverage (iOS/macOS/tvOS/watchOS/visionOS). Zero concurrency warnings under Swift 6 mode. DocC catalog builds natively in Xcode 26/27; CLI generation, if needed, uses `xcodebuild docbuild` (no `swift-docc-plugin` dependency — keep `dependencies: []` pristine).
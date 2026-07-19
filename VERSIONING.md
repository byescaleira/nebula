# Versioning — Nebula

Nebula versioning is **aligned 1:1 with the Apple OS version**. There is no separate major number to maintain — the library major *is* the OS major it targets. This mirrors the Cosmos sibling.

## Major version == OS version

A Nebula major release targets the matching OS major across all supported platforms:

| Nebula | iOS | macOS | tvOS | watchOS | visionOS | Era |
|--------|-----|-------|------|---------|----------|-----|
| **26** | 26 | 26 | 26 | 26 | 26 | Liquid Glass |

When a new OS major ships, Nebula bumps its major to match and may deprecate patterns tied to the prior OS.

## Meridian — sibling package, aligned to Nebula

Meridian (`Meridian/`, the presentation-architecture sibling that ships SwiftUI on top of Nebula's Foundation-only navigation model) is a **separate local SwiftPM package** with its own `Package.swift`, versioned **in lockstep with Nebula**: `Meridian N` ↔ `Nebula N` ↔ `OS N`. Meridian's major always equals Nebula's major at the same OS baseline (current: **Meridian 26 / Nebula 26 / OS 26**).

- Meridian depends on Nebula via `.package(name: "Nebula", path: "../")`; it is a subdir package in this repo (one repo, one CI), NOT a separate git remote. Promoting Meridian to its own public git repo + tag stream is a documented future step — until then it ships untagged alongside Nebula and is consumed by path.
- The same `swift-tools-version: 6.3` / `swiftLanguageModes: [.v6]` / all-5-platforms-`.v26` / `defaultLocalization: "en"` constraints apply. Meridian may freely `import SwiftUI` (that is its purpose); Nebula may NEVER `import Meridian` (hard compile error across packages — the Clean Architecture enforcement).
- "Available since Meridian 26" is not a separate `@available` stream — Meridian has no OS-introduced symbols of its own (it only re-exports Nebula's model and binds it to SwiftUI, both already at the `.v26` floor). Meridian minor/patch follow Nebula minor/patch within the Nebula 26 major; a Nebula major bump drags Meridian along.

## API availability == Nebula API versioning

Because the SwiftPM deployment target tracks the OS, `@available(iOS 26, *)` is the canonical way to express "available since Nebula 26". `@available` gates MUST include all 5 platforms: `@available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)`. Use `@available(*, deprecated, message:)` with a migration runway before `obsoleted:`. Centralize `if #available` gates for OS-introduced features rather than scattering them through the codebase.

Feature → OS gate reference (foundation-specific, verified against the Xcode 27 Beta.3 `.swiftinterface`):

| Feature | Gate |
|---|---|
| `os.OSLogType`, `os.Logger` (legacy), `String.Encoding`, `CharacterSet`, `Locale`, `Bundle` (`@unchecked Sendable`), `Data` base64 core, localizedStandardContains, localizedCompare family | iOS 8–15 / macOS 10.10–12 (floor — ungated) |
| `os.Logger` (modern), `OSLog.Category.pointsOfInterest` | iOS 14 / macOS 11 / tvOS 14 / watchOS 7 / visionOS 1 (floor — ungated) |
| `os.OSSignposter` / `OSSignpostID` / `OSSignpostIntervalState` / `SignpostMetadata` / `OSLogStore` / `OSLogEntry` / `getEntries` (OSLog.swiftmodule overlay, NOT os.swiftmodule) | iOS 15 / macOS 12 / tvOS 15 / watchOS 8 / visionOS 1 (floor — ungated) |
| `Mutex<T>` / `Atomic<T>` (`import Synchronization`, SwiftStdlib 6.0) | iOS 18 / macOS 15 / tvOS 18 / watchOS 11 / visionOS 2 (floor — ungated) |
| `FormatStyle` family (Date / ISO8601 / Decimal / Integer / FloatingPoint / Measurement / ByteCount / List / PersonNameComponents) + `ListFormatStyle` + `.list` accessor | iOS 15 / macOS 12 / tvOS 15 / watchOS 8 / visionOS 1 (floor — ungated) |
| `Date.RelativeFormatStyle` (init-based, NOT fluent chain; NO `.offset`/`.timer`/parameterless `static var relative`) | iOS 15 / macOS 12 (floor — ungated) |
| `Measurement<UnitInformationStorage>.FormatStyle.ByteCount` | iOS 16 / macOS 13 / tvOS 16 / watchOS 9 (floor — ungated) |
| `URL.FormatStyle` / `Duration.TimeFormatStyle` / `Duration.UnitsFormatStyle` / `Clock` / `Instant` / `ContinuousClock` / `SuspendingClock` (`_Concurrency`) | iOS 16 / macOS 13 / tvOS 16 / watchOS 9 / visionOS 1 (floor — ungated) |
| `Regex` / `RegexBuilder` / String algorithms / `AttributedString` / `AttributedString(localized:)` / `String(localized:)` / `LocalizedStringResource` | iOS 15–16 / macOS 12–13 (floor — ungated) |
| `NSDataDetector` (ObjC-bridged, cached in `Mutex<NSDataDetector?>`) | iOS 4 / macOS 10.7 / tvOS 9 / watchOS 2 / visionOS 1 (floor — ungated) |
| `CryptoKit` `SHA256` / `SHA384` / `SHA512` / `HashFunction` (only non-Foundation import, isolated behind `NebulaHashAlgorithm`) | iOS 13 / macOS 10.15 / watchOS 6 / tvOS 13 / visionOS 1 (floor — ungated) |
| `JSONDecoder` / `JSONEncoder` `@unchecked Sendable` | iOS 16 / macOS 13 (floor — ungated) |
| `CodableWithConfiguration` decode / encode overloads | iOS 17 / macOS 14 / visionOS 1+ (floor — ungated) |
| **At-floor — Nebula 26 == OS 26**, gate `@available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)` | |
| `DateComponents.formatted(_:)` / `DateComponents.init(_:strategy:)` / `DateComponents.ISO8601FormatStyle` + `.iso8601` static | iOS 26 / macOS 26 / tvOS 26 / watchOS 26 / visionOS 26 (at-floor — gate) |
| `CryptoKit.SHA2_256` typealias | iOS 26 / macOS 26 / tvOS 26 / watchOS 26 / visionOS 26 (at-floor — gate; `NebulaHashAlgorithm.sha2_256` alias) |
| Clean Architecture toolkit (`Sources/Nebula/Architecture/` — Domain/Ports/Errors/UseCase/Repository/Gateway/Validation/Registry/Testing/Async) | iOS 26 / macOS 26 / tvOS 26 / watchOS 26 / visionOS 26 (at-floor — "since Nebula 26"; the toolkit is pure Swift + Foundation + `Synchronization` and uses only below-floor primitives, so its types carry NO `@available` gate — the `.v26` deployment target makes them available on all 5 platforms. No above-floor gates.) |
| **Above-floor — Nebula 26.4**, gate `@available(iOS 26.4, macOS 26.4, tvOS 26.4, watchOS 26.4, visionOS 26.4, *)` | |
| `Data.Base64EncodingOptions.base64URLAlphabet` / `.omitPaddingCharacter` | iOS 26.4 / macOS 26.4 / tvOS 26.4 / watchOS 26.4 / visionOS 26.4 (above-floor — "since Nebula 26.4"; defer non-essential to Nebula 26.4) |
| `String.Encoding.ianaName` getter AND `init?(ianaName:)` | iOS 26.4 / macOS 26.4 / tvOS 26.4 / watchOS 26.4 / visionOS 26.4 (above-floor — "since Nebula 26.4") |
| `UUID.random(using:)` (swift-foundation SF-0031 / FoundationPreview 6.3, surfaced as OS 26.4; NOT parameterless `random()`) | iOS 26.4 / macOS 26.4 / tvOS 26.4 / watchOS 26.4 / visionOS 26.4 (above-floor — "since Nebula 26.4"; `UUID()` remains the default random v4 generator) |
| **Above-floor — Nebula 27**, gate `#if swift(>=6.4)` + `if #available(iOS 27, macOS 27, tvOS 27, watchOS 27, visionOS 27, *)` | |
| OS-27-only SDK symbols (none identified yet in foundation scope; mechanic established for parity with Cosmos) | iOS 27+ / macOS 27+ / tvOS 27+ / watchOS 27+ / visionOS 27+ (combined compile + runtime gate; graceful fallback on Swift 6.3 / OS 26) |
| **macOS-only** (gate `#if os(macOS)` or explicit per-platform `@available(<platform>, unavailable)` — NOT `@available(macOS 12, *)` alone, whose `*` fallback enables all platforms) | |
| `NebulaLogStoreExporter.Scope.system` / `NebulaLogStoreExporter.local()` | macOS-only (visionOS availability uncertain from headers → conservatively gate unavailable on visionOS). **Deferred** — not shipped in 0.1.0; tracked in `ROADMAP.md` → "Later". The mechanic (`#if os(macOS)` + explicit per-platform unavailable) stands for when it lands. |

The entire core FormatStyle family (incl. `ListFormatStyle` + `.list` accessor — verified at `Foundation.swiftinterface:20823/20892`) is at the SAME floor `macOS 12 / iOS 15 / tvOS 15 / watchOS 8` — NOT macOS 13/iOS 16/watchOS 9 as originally claimed. Only `URL.FormatStyle` and `Duration.TimeFormatStyle`/`UnitsFormatStyle` require macOS 13/iOS 16/tvOS 16/watchOS 9 (still below `.v26`).

`Mutex<T>` / `Atomic<T>` require iOS 18 / macOS 15 / tvOS 18 / watchOS 11 / visionOS 2 (SwiftStdlib 6.0 — below the `.v26` floor, no gating needed). `NebulaMemoryLogHandler`'s effective floor is iOS 18/macOS 15/visionOS 2 via `Mutex`.

## Deprecation runway

1. Mark `@available(*, deprecated, message: "Use <replacement>; removed in Nebula <N+1>.")`.
2. Keep working for at least one minor release.
3. Remove (or mark `obsoleted:`) at the next major.

## Within a major: semantic minor/patch

- **Patch** (`26.0.x`): bug fixes, no API or behavior change.
- **Minor** (`26.x.0`): additive APIs, new extensions, non-breaking contract additions. Backwards-compatible. Above-floor minor-OS bumps (e.g. Nebula 26.4 surfaces) ship here.
- **Major** (`N+1.0.0`): aligns to a new OS major; may remove APIs deprecated in the prior major (after the runway) and change the foundation surface.

## Changelog

Every release records changes under Keep-a-Changelog-style sections in `CHANGELOG.md`, with the Nebula/OS version alignment noted at the top of the entry.
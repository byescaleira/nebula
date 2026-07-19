# Architecture: Nebula

## Overview

Nebula is a multi-platform Swift foundation/architecture library distributed as an SPM package — the sibling of Cosmos (the SwiftUI design system). It is **not** a UI library. It begins with four `Sendable` value-type configuration structs and a `Sendable` error envelope, plus extensions on Foundation value types:

- `NebulaLogConfiguration` — logging behavior: level, category, subsystem, min level, `@Sendable` handler.
- `NebulaErrorConfiguration` — error reporting: isEnabled, category, `@Sendable` handler.
- `NebulaStandards` — formatting policy: locale, timeZone, calendar, FormatStyle accessors.
- `NebulaMeasureConfiguration` — measurement: clock, signposter, enabled, handler.
- `NebulaError` — `Error`/`LocalizedError`/`CustomNSError`/`Sendable`/`Hashable` envelope with lossy mapping from `NSError`/`DecodingError`/`URLError`/`CocoaError`/`any Error`.

Every contract is a `Sendable` struct with a `@Sendable` handler and fluent `.with*` builders — mirroring `CosmosConfiguration`/`CosmosLogConfiguration`/`CosmosErrorConfiguration` minus the SwiftUI `@Entry`/`@Observable` plumbing. Apps inject explicitly (process-wide `Mutex<Nebula*Config>` accessor or explicit-parameter DI); there is no SwiftUI environment.

## Goals

1. **Apple-native primitives only:** `os.Logger`/`OSSignposter`, `FormatStyle` family, `Measurement`, `Regex`, `AttributedString`, `Duration`/`Clock`, `Mutex`/`Atomic`. No `swift-log`, no legacy `Formatter` subclasses in the public surface.
2. **Concurrency safety:** Swift 6 strict mode; every public type `Sendable`; zero concurrency warnings; `Mutex`/`Atomic` from `Synchronization`; no `NSLock`/`DispatchQueue`/`nonisolated(unsafe)`.
3. **One import:** a single `Nebula` target exposes logging, errors, extensions, formatting, and measurement through one `import Nebula`.
4. **Lossy-but-Sendable error mapping:** `any Error` is not `Sendable` — mapping inits consume the existential at construction time and keep only Sendable fragments; `NebulaError` is a concrete `Sendable: Error` for typed-throws consumers.
5. **Apple-aligned:** modern APIs over legacy; `@available` gates include all 5 platforms incl. `visionOS 26`; DocC documentation.
6. **Testability:** value types and plain contracts are easy to unit-test off the main actor.

## Non-goals

- Backwards compatibility with pre-v26 Apple platforms (Nebula major == OS major; baseline Nebula 26).
- UIKit support or any explicit UIKit dependency.
- SwiftUI environment integration or any `@Entry`/`@Observable`/`@Environment` surface (apps inject explicitly).
- UI/presentation layer (Nebula reports, it does not present — mirrors Cosmos).
- `RecoverableError` adoption (AppKit-oriented, escaping closure, not multiplatform-Sendable-friendly).
- Back-deployment via `FoundationPreview` in v1 (Apple-platform-only at `.v26`).
- Runtime theming engine (static configurations only).

## Stack

- Swift 6.3+ toolchain (dual Xcode 26.4+ / Xcode 27 build), language mode v6, Xcode 26.4+
- Foundation + os + Synchronization + _Concurrency + CryptoKit (only behind `NebulaHashAlgorithm`)
- Swift Testing
- DocC

## Structure

```
Nebula/
├── Sources/Nebula/          # Single SPM target
│   ├── Nebula.swift         # `Nebula` enum + `NebulaVersion` (Nebula N == OS N baseline)
│   ├── Nebula.docc/         # DocC catalog (auto-discovered)
│   ├── Logging/             # os.Logger façade + signposter + memory handler
│   ├── Errors/              # NebulaError envelope + Box + configuration + lossy mapping
│   ├── Extensions/          # DateTime/ String/ Number/ Primitive/ Collection/ Codable/ DataURL
│   ├── Standardize/         # NebulaStandards + NebulaStandardsConfig (FormatStyle façades)
│   ├── Measure/             # NebulaMeasureConfiguration + NebulaMeasureResult + NebulaMeasureConfig
│   └── Architecture/        # Clean Architecture toolkit — seams only (domain/ports/use case/repository/gateway/validation/registry/testing/async) + Presentation/ (Foundation-only nav model)
└── Tests/
    └── NebulaTests/          # Swift Testing — mirrors source layout

Meridian/                      # Sibling SPM package (SwiftUI) — depends on Nebula via ../
├── Sources/Meridian/         # @Observable Router + MeridianNavigationStack + DocC
├── Sources/MeridianExample/  # @main App — compile gate / living docs (NOT shipped)
└── Tests/MeridianTests/      # Swift Testing — Router / DeepLink / Destination
```

## Configuration contracts

All four contracts are `Sendable` `struct` value types. Mutations happen by replacement via fluent `.with*` builders returning a copy (mirror Cosmos):

```swift
let log = NebulaLogConfiguration.default
    .withSubsystem("com.example.app")
    .withMinLevel(.info)
    .withHandler { event in /* @Sendable */ }

NebulaErrorConfig.set(
    NebulaErrorConfiguration.default
        .withCategory("App")
        .withHandler { event in /* @Sendable */ }
)

let standards = NebulaStandards.default
    .withLocale(Locale(identifier: "en_US_POSIX"))
    .withTimeZone(.gmt)
```

There is no `@Entry` environment value and no `@Observable` runtime theme. Apps either set a process-wide default via `Nebula*Config.set(_:)` (Mutex-backed) or pass a configuration explicitly as a parameter. Both paths are supported — global Mutex default for ergonomics, explicit parameter for testability.

## Logging

`Sources/Nebula/Logging/` is a thin Sendable façade over the native `os.Logger` / `OSSignposter` unified-logging stack (no `swift-log`, no third-party deps).

| Type | Responsibility |
|---|---|
| `NebulaLogLevel` | enum Int Sendable mapping 1:1 to `os.OSLogType` (debug/info/notice/error/fault; `warning` alias = error — verified `Logger.warning` → `.error`). |
| `NebulaLogCategory` | Sendable `ExpressibleByStringLiteral` struct with presets (`.networking`/`.persistence`/`.formatting`/`.measure`/`.concurrency`/`.general`). |
| `NebulaLogger` | Sendable struct façade over `os.Logger` (`@unchecked Sendable`, iOS 14+); `init(subsystem:category:)`, `isEnabled(_:)`, `debug`/`info`/`notice`/`warning`/`error`/`fault`/`log(level:_:)` (String convenience path — builds the `OSLogMessage` literal at the call site so it compiles under `oslog.log_with_level`; defaults `.public`, NO per-argument redaction). Exposes `public var osLogger: os.Logger` as the redaction-preserving path (the `OSLogMessage` literal must appear directly at an `os.Logger` call site — `os.Logger` cannot be wrapped, compile-verified). `var signposter: NebulaSignposter`. |
| `NebulaLogEvent` | Sendable struct (category/level/message/date) for the handler fan-out path. |
| `NebulaLogConfiguration` | Sendable struct + `@Sendable` handler + `.with*` builders + `static let default`. `logger()` builds a `NebulaLogger`; `log(_:_:)` is the String convenience path (defaults `.public`, loses per-argument redaction — document loudly). |
| `NebulaSignposter` | Sendable struct over `os.OSSignposter` (iOS 15+); exposes `public var osSignposter` for `emitEvent`/`beginInterval`/`endInterval`/`withIntervalSignpost` (the `StaticString`/`SignpostMetadata` literals must appear at the `os.OSSignposter` call site — cannot be wrapped, compile-verified); keeps Nebula-typed `makeSignpostID`/ID/state wrappers (no-literal ops). |
| `NebulaSignpostID`/`NebulaSignpostIntervalState`/`NebulaSignpostMetadata` | Sendable wrappers over the os signpost types (metadata is a `typealias = os.SignpostMetadata`). |
| `NebulaMemoryLogHandler` | `final class @unchecked Sendable` in-memory ring buffer for tests/preview; `Mutex<T>`-backed (effective floor iOS 18/macOS 15/visionOS 2 — below `.v26`). The ONLY `@unchecked Sendable` in the codebase — a reference type, not a value type, so it does not violate the "derive Sendable, never `@unchecked` on a Nebula-defined value type" rule. |

**Deferred**: `NebulaLogStoreExporter`/`NebulaLogStoreEntry` (macOS-only `os.OSLogStore` exporter — `#if os(macOS)` + explicit per-platform unavailable; visionOS availability uncertain → conservatively gate unavailable) is tracked in `ROADMAP.md` → "Later". `OSMetricOperation` (OS 26 signpost-metrics) is `internal` in the os overlay — cannot be re-exported; if metric APIs are needed, Nebula defines its own public operation enum gated `@available(iOS 26, *)` (deferred to Nebula 27).

## Errors

`Sources/Nebula/Errors/` is a Sendable value-typed envelope plus a configuration contract mirroring `CosmosErrorConfiguration`.

| Type | Responsibility |
|---|---|
| `NebulaError` | `Error`/`LocalizedError`/`CustomNSError`/`Sendable`/`Hashable` envelope: `code`/`kind`/`message`/`failureReason`/`recoverySuggestions[]`/`helpAnchor`/`metadata`/`context`/`date`/`underlying: Box?`. |
| `NebulaError.Code` | `Sendable`, `Hashable` struct `(domain: String, code: Int)` — stable identity across NSError/Swift. |
| `NebulaError.Kind` | `String, Sendable, CaseIterable` enum (network/decoding/encoding/cocoa/file/validation/serialization/unknown). |
| `NebulaError.Context` | `Sendable`, `Hashable` struct (codingPath `[String]`, debugDescription, source). |
| `NebulaError.Box` | `final class: Sendable, Hashable` — reference box holding a nested `NebulaError` (required because a Swift `struct` cannot recursively contain itself; `underlying: NebulaError?` does NOT compile). Derived `Sendable` on a final class with a Sendable `let`; no `@unchecked`. |
| `NebulaErrorConfiguration` | `Sendable` ONLY (NOT `Equatable` — the `@Sendable` handler closure is not `Equatable`, mirroring `CosmosErrorConfiguration`). Fluent `.with*` builders; `static let default`. |
| `NebulaErrorEvent` | `Sendable`, `Equatable` struct (category, error, date) — Equatable valid (all fields Equatable). |
| `NebulaErrorConfig` | Process-wide `Mutex<NebulaErrorConfiguration>` accessor (`get()`/`set(_:)`). |
| `NebulaDecodingError`/`NebulaEncodingError` | Sendable mirrors of `DecodingError`/`EncodingError` (Kind, codingPath `[String]`, debugDescription, underlyingErrorDescription). |

**Lossy mapping inits** (`NebulaError+Mapping.swift`): `init(_ nsError: NSError)`, `init(decodingError:)`, `init(urlError:)`, `init(cocoaError:)`, `init(error: any Error)` — the underlying `any Error` is consumed at construction time and NOT retained (not `Sendable`); only Sendable fragments survive. `NebulaError.wrap(_:)` wraps any throwing closure into `Result<T, NebulaError>`.

**Typed-throws policy**: untyped `throws` is the default for all public Nebula APIs (SE-0413 evolution safety); `NebulaError` is exposed as an opt-in concrete `Failure` for `throws(NebulaError)` / `Result<T, NebulaError>`. `RecoverableError` is deliberately NOT adopted (AppKit-oriented, escaping closure, not multiplatform-Sendable-friendly); `recoverySuggestions[]` is surfaced via `LocalizedError.recoverySuggestion`.

## Extensions

`Sources/Nebula/Extensions/` hosts value-type extensions on Foundation primitives, grouped by concern. All derive `Sendable`; no `@unchecked` on Nebula types; no legacy `Formatter` subclasses.

| Folder | Coverage |
|---|---|
| `DateTime/` | `Date` arithmetic/predicates (startOfDay/endOfDay/startOfWeek/…, DST-safe via `calendar.dateInterval(of:for:)`), `DateComponents` builders, `DateInterval.init(start:duration: Swift.Duration)` (distinct from Foundation's TimeInterval overload), `NebulaDateFormat`/`NebulaDurationFormat` façades. No `Calendar.gregorian` static (does not exist — use `Calendar(identifier: .gregorian)`); `RelativeFormatStyle` via init (no fluent chain, no `.offset`/`.timer`). ISO/stable presets pinned to `Locale(identifier: "en_US_POSIX")` + `.gmt`. (No `NebulaClock` — deferred; measure uses `any Clock<Duration>` directly.) |
| `String/` | `isBlank`/`trimmed`/`truncated`/case conversions/base64/hex/URL extraction; `NebulaRegex<Output>` (Sendable, conditional `where Output: Sendable`); `NebulaRegexPatterns` (curated literals: UUID/IPv4/hex/semver/ISO-timestamp — NO email, per Apple guidance); `NebulaStringDetectedEntity` over `NSDataDetector` (cached in `Mutex<NSDataDetector?>`); `NebulaStringLocalization` (Sendable struct over `String(localized:)` + `AttributedString(localized:)`, Foundation scope only — no SwiftUI/UIKit scopes). |
| `Number/` | `NebulaFormattingOptions` (Sendable + `.with*`) + `NebulaNumberFormatting` façade (percent/currency/bytes/list/measurement); `BinaryInteger`/`BinaryFloatingPoint`/`Decimal` extensions (clamped/rounded/isWholeNumber/measured(in:)). `Decimal.rounded(toDecimalPlaces:)` via `NSDecimalRound` (C) + `NSDecimalNumber.RoundingMode` (Decimal has NO value-level `rounded(_:)` — verified). `Decimal.FormatStyle` is its own struct (Decimal does NOT conform to `FloatingPoint`). |
| `Primitive/` | `Comparable.clamped(to:)` (fills SE-0177 gap), `BinaryInteger.isEven`/`isOdd`/`times(_:)` (non-escaping rethrows — matches `forEach`), `Optional.or(_:)`/`orThrow(_:)`/`isNilOrEmpty`, `NebulaNilError` (concrete Sendable), `UUID.shortString`/`isValid(_:)`. Gate `UUID.nebulaRandom()` at `@available(iOS 26.4, *)` (wraps `random(using:)` — `UUID()` remains the default random v4 generator). NEVER redeclare `Bool.toggle()`/`isMultiple(of:)`. |
| `Collection/` | `nebulaChunked(byCount:)`/`nebulaWindows(ofCount:)`/`nebulaUniqued(on:)`/`nebulaStablePartition(by:)`/`nebulaPartitioned(by:)`/`nebulaSorted(_:)` key-path/`nebulaMerging`. `nebula*` prefix on open `Collection`/`Sequence` (no stdlib pollution). Eager by default (conscious divergence from swift-algorithms' lazy `uniqued()`); non-escaping `rethrows` closures (NOT `@escaping @Sendable`). (`nebulaFiltered(by:)` over `Foundation.Predicate` and `NebulaFrequency` are deferred to post-0.1.0.) |
| `Codable/` | `NebulaJSONDecoder`/`NebulaJSONEncoder` (Sendable wrappers holding a configure-once-frozen `JSONDecoder`/`JSONEncoder` in a `let`); `NebulaJSONDecoderConfiguration`/`NebulaJSONEncoderConfiguration` (Sendable + `.with*`, all strategy enums Sendable); `NebulaDecodingError`/`NebulaEncodingError` + `DecodingError.nebula`/`NebulaError.decoding(_:)` bridges; `Decodable.init(fromJSON:)`/`Encodable.toJSONData`. NO `OutputFormatting.fragmentsAllowed` (does not exist — that's `JSONSerialization.WritingOptions`; `ReadingOptions` uses `.allowFragments`). |
| `DataURL/` | `Data.nebulaHexEncodedString`/`init?(nebulaHexEncoded:)` (Foundation has NO native hex); `NebulaHashAlgorithm` (Sendable enum over CryptoKit SHA256/384/512 — the ONLY `import CryptoKit`); `Data.nebulaDigest`/`nebulaHexDigest`; `URL.nebulaAppending(queryItem:)`/`nebulaSettingQueryItem`/`nebulaRemovingQueryItem`/`nebulaQueryItem(named:)`/`nebulaPercentEncoded()`; `URLComponents.nebulaWith(queryItem:)` fluent builders. Defer base64URL/omitPadding to Nebula 26.4. |

## Standardize

`Sources/Nebula/Standardize/` hosts `NebulaStandards` (+ `NebulaStandardsConfig`, the process-wide `Mutex` accessor) — a single Sendable façade over Foundation's modern `FormatStyle` family (Date/ISO8601/Decimal/Integer/FloatingPoint/Measurement/Currency/Percent/ByteCount/List/PersonNameComponents/URL/Duration). It pre-configures locale/timeZone/calendar once and returns Sendable `FormatStyle` values callers can chain (`.attributed`, `.precision`, `.grouping`, `.locale`, `.notation`). No legacy `NumberFormatter`/`DateFormatter`/`MeasurementFormatter`/`ByteCountFormatter`/`ISO8601DateFormatter` (superseded; `ListFormatter` wrapped per-call only — no FormatStyle replacement, not Sendable).

| Method | Returns |
|---|---|
| `date` / `iso8601` / `date(verbatim:)` | `Date.FormatStyle` / `Date.ISO8601FormatStyle` / `Date.VerbatimFormatStyle` |
| `decimal` / `integer<Value>()` / `double<Value>()` / `percent<Value>()` / `currency<Value>(code:)` | `Decimal.FormatStyle` / `IntegerFormatStyle` / `FloatingPointFormatStyle` / `.Percent` / `.Currency` |
| `byteCount(style:)` / `list(memberStyle:type:width:)` / `name` | `ByteCountFormatStyle` / `ListFormatStyle` / `PersonNameComponents.FormatStyle` |
| `measurement<U>(width:usage:numberFormatStyle:)` | `Measurement<U>.FormatStyle` (width/usage/numberFormatStyle — NO `unit` param; unit is implied by the `Measurement<U>` value) |
| `duration(units:width:maximumUnitCount:)` / `duration(pattern:)` | `Duration.UnitsFormatStyle` (`Set<Duration.UnitsFormatStyle.Unit>` — NOT `[Duration.Unit]`; there is NO top-level `Duration.Unit`) / `Duration.TimeFormatStyle` |
| `url` | `URL.FormatStyle` (iOS 16+) |
| `string(_:format:)` / `attributed(_:format:)` | convenience `String` / `AttributedString` (Sendable, iOS 15+) |

Gate `DateComponents.formatted(_:)` + `DateComponents.ISO8601FormatStyle` + `.iso8601` static at `@available(iOS 26, *)` (whole DateComponents formatting family is at-floor).

## Measure

`Sources/Nebula/Measure/` hosts the 4th configuration contract, pairing `Clock`/`Duration` (`_Concurrency`) for timing with `os.OSSignposter` for Instruments integration. Signpost integration lives on `NebulaSignposter` (under Logging); `NebulaMeasureConfiguration` is the contract that carries the measurement API — mirroring `NebulaLogConfiguration.log` — rather than a separate `NebulaMeasure` type.

| Type | Responsibility |
|---|---|
| `NebulaMeasureConfiguration` | Sendable struct (the 4th config contract): clock (`any Clock<Duration>`, default `ContinuousClock`), signposter, enabled, `@Sendable` handler, fluent `.with*`. Carries `measure(_:operation:)` sync+async (returning `(T, Duration)`) and `bench(_:iterations:warmup:operation:)` micro-bench ON the config. |
| `NebulaMeasureResult` | Sendable struct (name, iterations, total Duration, perIteration, components). Minimal for v1 (no p50/p99 — deferred). |
| `NebulaMeasureConfig` | Process-wide `Mutex<NebulaMeasureConfiguration>` accessor (`get()`/`set(_:)`). |

`ContinuousClock` counts sleep; `SuspendingClock` does not (WWDC22 110355) — document the choice so users pick the right clock. `bench()` is a quick micro-bench, not statistically rigorous (no p50/p99 yet).

**Deferred**: `NebulaClock` (ContinuousClock/SuspendingClock wrapper) — `NebulaMeasureConfiguration` uses `any Clock<Duration>` directly. Tracked in `ROADMAP.md` → "Later".

## Architecture

`Sources/Nebula/Architecture/` is the **second surface** of Nebula: the Clean Architecture toolkit. It ships **only the seams** — inner-owned marker protocols, a DTO contract, repository/gateway ports, a use-case type, validators, a registry, test doubles, async-flow helpers, and the Foundation-only navigation model — so an app can implement Clean Architecture efficiently without Nebula owning any database or framework code. Concrete adapters (repositories, gateways, presenters, URLSession networking) live in the app; the SwiftUI presentation layer lives in the **Meridian** sibling package (`Meridian/`, see [Presentation (Meridian)](#presentation-meridian)). Nebula itself owns no presenter and no SwiftUI. The toolkit is pure Swift + Foundation + `Synchronization`; every symbol sits at the Nebula 26 floor (no above-floor gates). The DocC catalog (`Sources/Nebula/Nebula.docc/Architecture.md`) is the canonical article.

| Subtree | Responsibility |
|---|---|
| `Domain/` | Markers `NebulaValue`/`NebulaEntity`/`NebulaAggregate` + the phantom-typed `NebulaID` identity value. |
| `Ports/` | Bare `Sendable` markers `NebulaInputPort`/`NebulaOutputPort`/`NebulaDTO`. Nebula defines no presenter. |
| `Errors/` | `NebulaFailure` protocol + per-layer open structs (`NebulaDomainError`, `NebulaValidationError`) bridging to the closed `NebulaError.Kind` via a caller-picked `toNebulaError(kind:)`. No new `Kind` cases. |
| `UseCase/` | `NebulaUseCase<I, O>` generic `Sendable` struct over a `@Sendable` async body + `NebulaUseCaseRole` (command/query); `.logged`/`.measured`/`.reported`/`.instrumented` decorators route to the existing configs (no 5th config); `executeTyped(_:) async throws(NebulaError)`. |
| `Repository/` | Capability protocols (`NebulaRepository` / read-only / keyed / writable / deletable) + `NebulaRepositoryError`. No CRUD mandate, no `update` verb. |
| `Gateway/` | `NebulaGateway` marker + `NebulaGatewayConfiguration` (reuses `NebulaJSONDecoder`/`Encoder`) + `NebulaGatewayConfig` accessor. Concrete HTTP gateway deferred. |
| `Validation/` | `NebulaValidator<T>` (sync, short-circuit) + `NebulaAsyncValidator<T>` (async; a thrown I/O error is distinct from a validation failure). |
| `Registry/` | `NebulaRegistryKey` (open struct) + `NebulaRegistryConfiguration` + `NebulaRegistry` (explicit injection) + `NebulaRegistryConfig` (process-wide). DI **without** a container. |
| `Testing/` | In-target test doubles `NebulaFakeRepository`/`NebulaStubUseCase`/`NebulaSpyUseCase` (`final class` + `let Mutex`; `Sendable` **derived** — final class with all-`let` `Sendable` properties, no `@unchecked`). |
| `Async/` | `NebulaResultPipeline<T>` (`map`/`flatMap`/`recover` over `Result<T, NebulaError>`) + `AsyncSequence.nebulaChunked(byCount:)`/`nebulaUniqued(on:)`. |
| `Presentation/` | Foundation-only navigation model: `NebulaRoute` (marker: `Hashable`/`Sendable`/`Codable`), `NebulaNavigationStack<Route>` (the typed `[Route]` stack — single source of truth via `static` stack mutators), `NebulaRouter<Route>: Sendable` (**async** navigation-intent port), `NebulaViewModel` (bare marker), `NebulaSpyRouter<Route>` (test double). No SwiftUI here — Meridian binds it. |

All public value types derive `Sendable`. The toolkit introduces **no** `@unchecked Sendable`: the two `final class` test-helpers (`NebulaFakeRepository`, `NebulaSpyUseCase`) derive `Sendable` (a `final class` with all-`let` `Sendable` properties synthesizes `Sendable`; `Mutex` is `Sendable` when its value is), needing no `@unchecked`. They are `final class` rather than `struct` because a `Mutex`-typed stored property propagates `~Copyable` to an owning *struct* — a non-copyable double is awkward to pass around a test; the class absorbs the `~Copyable` `Mutex` behind a copyable reference (the `NebulaError.Box` derived-Sendable-`final class` precedent, not the `NebulaMemoryLogHandler` `@unchecked` exception). The 10 locked design decisions and the consolidated risks live in the vault (`03-padroes/nebula-clean-architecture-toolkit.md`, `08-riscos/clean-architecture-toolkit-risks.md`, `08-riscos/clean-architecture-open-questions.md`); the ADR is in `DECISIONS.md`.

<a name="presentation-meridian"></a>

## Presentation (Meridian)

The presentation architecture is **MVVM `@Observable` + native typed-`[Route]` Router pattern** (no Coordinator tree — owner preference). It is split across two packages so the Clean Architecture dependency rule is **compiler-enforced**, not convention:

- **Nebula** ships the Foundation-only **navigation model** under `Sources/Nebula/Architecture/Presentation/`: `NebulaRoute` (the route contract: `Hashable`/`Sendable`/`Codable`), `NebulaNavigationStack<Route>` (the typed `[Route]` stack — the "real navigation model" that holds push/pop/popToRoot/replaceStack logic once, in `static` mutators, with instance API delegating), `NebulaRouter<Route>: Sendable` (the **async** navigation-intent port), `NebulaViewModel` (a bare `Sendable` marker — Nebula ships no `@Observable`), and `NebulaSpyRouter<Route>` (a `Mutex`-backed test double). None of this imports SwiftUI.
- **Meridian** (`Meridian/`, a separate local SwiftPM package depending on Nebula via `../`) ships the SwiftUI binding: `@MainActor @Observable public final class Router<Route: NebulaRoute>: NebulaRouter<Route>` and `MeridianNavigationStack` (a `NavigationStack(path:)` + `navigationDestination(for:)` wrapper). One `Router`/`MeridianNavigationStack` per tab.

**Why the port is async.** Nebula has no default actor isolation (no SwiftUI → no `@MainActor`), yet the concrete `@MainActor @Observable` Meridian `Router` must conform to a Nebula port. The fix is the canonical Swift 6 idiom: `NebulaRouter`'s requirements are `async`; a synchronous `@MainActor` method **witnesses a nonisolated async requirement** (the `await` performs the actor hop). This keeps Nebula `@MainActor`-free while letting the on-actor `@Observable` Router conform — no SE-0411 isolated conformances (experimental/above-floor), no `@unchecked Sendable` on the Router (it is `Sendable` by `@MainActor` isolation). The async port is also the **cross-actor bridge**: a non-MainActor deep-link parser can `await router.replaceStack(with:)` to drive the UI.

**Why a sibling package.** Meridian is a *separate* package so `import Meridian` from inside Nebula is an unconditional hard compile error — the Clean Architecture rule "use cases / domain never import presentation" is enforced across packages (SR-1393 only blocks cross-module access *within one package's* `.build`; a separate module graph defeats it). This closes the Wave H open risk. Meridian lives as a subdir package (`Meridian/`, `path: "../`) in this repo — one repo, one CI; promoting it to its own public git repo is a documented future step. Versioning: Meridian N ↔ Nebula N ↔ OS N, in lockstep (`VERSIONING.md`).

Two patterns the foundation enables (DocC article `Meridian.docc/NavigationPatterns.md`, runnable `MeridianExample` executable as compile gate): **deep link as data** — a pure `URL → [Route]` function, asserted as a value, then `router.replaceStack(with:)`; and **type-driven modal destinations** — a single `Optional<Destination>` enum drives `sheet(item:)`, so "edit sheet AND delete alert showing" is a state the compiler refuses (no `@CasePathable` macro — `dependencies: []`). Vault: `03-padroes/nebula-presentation-architecture.md`, `nebula-presentation-seams.md`, `nebula-meridian-router.md`, `nebula-presentation-destinations-deeplink.md`; risks `08-riscos/presentation-architecture-risks.md`; ADR in `DECISIONS.md`.

## Concurrency

There is **no** `Sources/Nebula/Concurrency/` directory and **no** `NebulaLocked`/`NebulaFlag`/`NebulaOnce` wrapper layer shipped in 0.1.0. Nebula's shared mutable state uses `Mutex<T>`/`Atomic<T>` from `import Synchronization` directly (process-wide config accessors are `let Mutex<…>` globals; `NebulaMemoryLogHandler` backs its ring buffer with a `Mutex`). The `~Copyable`/`Sendable` Nebula-prefixed wrappers were designed (see `DECISIONS.md` ADR row "Ship `NebulaLocked`/`NebulaFlag`/`NebulaOnce` wrappers") but deferred — their `~Copyable`+`Sendable` synthesis still needs compile-validation against the exact Swift 6.4 toolchain. Tracked in `ROADMAP.md` → "Later".

The Swift 6 concurrency rules that the wrappers would have embodied still apply throughout the codebase (see `CLAUDE.md` → "Concurrency — Modern Swift 6, zero warnings"): all public value types `Sendable` by derived conformance (no `@unchecked` on Nebula-defined value types); handlers `@Sendable`; `Mutex.withLock` uses `sending` (SE-0430, NOT `transferring`); the three frozen ordering structs `AtomicLoadOrdering`/`AtomicStoreOrdering`/`AtomicUpdateOrdering` (`.acquiringAndReleasing` is invalid for `load`); region-based isolation (SE-0414) before `@unchecked`; actors not global actors.

## Conventions

- All public types are prefixed with `Nebula` (top-level types) or use natural names on extension methods that fill a stdlib gap (`clamped(to:)`, `or(_:)`).
- `nebula*` method-label prefix on open `Collection`/`Sequence` ergonomics to avoid stdlib namespace pollution.
- Configurations are `Sendable` structs with `@Sendable` handlers and fluent `.with*` builders — no `@Entry`, no `@Observable`, no `@Environment`.
- Extensions derive `Sendable`; no `@unchecked Sendable` on Nebula-defined types.
- `@available` gates include all 5 platforms: `@available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)`.
- macOS-only gating uses `#if os(macOS)` or explicit per-platform `@available(<platform>, unavailable)` — NOT `@available(macOS 12, *)` alone.
- DocC on every public symbol.
- The `.swiftinterface` (Xcode 27 Beta 3 SDK) is the authoritative ground truth for Apple API availability — not WebFetch (which has hallucinated availability tables).

## Dependencies

- None at runtime.
- Swift Testing is part of the Swift toolchain.
- CryptoKit is an Apple framework (allowed); the only non-Foundation import, isolated behind `NebulaHashAlgorithm` in `Extensions/DataURL/`.

## Targets

`Nebula` ships as a single SPM target. Consumers import one module:

```swift
import Nebula
```

This keeps the public surface simple while still organizing code internally as `Nebula.swift` (top-level), `Logging`, `Errors`, `Extensions`, `Standardize`, and `Measure`.
---
tags: [foundation, standardize, measure, formatting, signposts, duration, clock]
aliases: [nebula-standards, nebula-measure, padronizar-medir]
related: [[nebula-logging], [nebula-errors], [nebula-date-time-extensions], [nebula-string-extensions], [nebula-number-measurement-extensions], [nebula-primitive-extensions], [nebula-collection-extensions], [nebula-codable-foundation], [nebula-data-url-extensions], [nebula-spm-architecture], [nebula-swift6-concurrency]]
---

# Nebula Standardize/Measure Subsystem

The unified **padronizar/medir** subsystem for Nebula. Two halves, one coherent design:

- **STANDARDIZE** — `NebulaStandards`: a single Sendable facade over Foundation's modern `FormatStyle` family (Date, ISO8601, Decimal, Integer, FloatingPoint, Measurement, Currency, Percent, ByteCount, List, PersonNameComponents, URL, Duration), producing `String` or `AttributedString`, locale/timeZone/calendar-aware.
- **MEASURE** — `NebulaMeasure` + `NebulaSignposter`: timing via `Clock`/`Instant`/`Duration` (`_Concurrency`, Swift 5.7) plus `os.OSSignposter`/`Logger.signpost` for Instruments integration, tied to the same `os.Logger` category as [[nebula-logging]].

> **Verification note (adversarial re-check against Xcode 27 Beta.3 SDK):** The original research claimed `ListFormatStyle` requires macOS 13/iOS 16/watchOS 9. That is **wrong**. `ListFormatStyle` and the `.list(memberStyle:type:width:)` accessor are `@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)` (Foundation.swiftinterface:20823/20892) — the same floor as the core family. The watchOS-9-requiring APIs in scope are `URL.FormatStyle`, `Duration.TimeFormatStyle`/`UnitsFormatStyle`, and `Clock`/`Duration` themselves. Two accessor signatures were also corrected: `Duration.UnitsFormatStyle` takes `Set<Duration.UnitsFormatStyle.Unit>` (there is no top-level `Duration.Unit`), and `Measurement<U>.FormatStyle` is constructed with `width`/`usage`/`numberFormatStyle` (no `unit` parameter — the unit is implied by the `Measurement<U>` value being formatted). The OS-26 at-floor claim for `DateComponents.formatted(_:)` is confirmed, and the sibling `DateComponents.ISO8601FormatStyle` + `.iso8601` static (interface ~8390) is ALSO OS 26 — added as a risk.

## Ground truth: Foundation FormatStyle family

Verified against `Foundation.swiftmodule/arm64e-apple-macos.swiftinterface` (MacOSX27.0.sdk / Xcode 27 Beta.3). All modern `FormatStyle` types are **at-or-below the .v26 floor**:

| Symbol | .swiftinterface line | Availability |
|---|---|---|
| `protocol FormatStyle<FormatInput,FormatOutput>` | :8471 | macOS 12 / iOS 15 / tvOS 15 / watchOS 8 |
| `protocol ParseableFormatStyle`, `ParseStrategy` | :8482 / :8487 | macOS 12 / iOS 15 / tvOS 15 / watchOS 8 |
| `Date.FormatStyle`, `.AttributedStyle`, `.ParseStrategy` | :19104 / :19122 / :19314 | macOS 12 / iOS 15 / tvOS 15 / watchOS 8 |
| `Date.ISO8601FormatStyle` + `static iso8601` | :8202 / :8296 | macOS 12 / iOS 15 / tvOS 15 / watchOS 8 |
| `Date.VerbatimFormatStyle` | :18437 | macOS 12 / iOS 15 / tvOS 15 / watchOS 8 |
| `Decimal.FormatStyle` + `.attributed` | :19389 / :19461 | macOS 12 / iOS 15 / tvOS 15 / watchOS 8 |
| `FloatingPointFormatStyle<Value>` + `.attributed` | :19637 / :19805 | macOS 12 / iOS 15 / tvOS 15 / watchOS 8 |
| `IntegerFormatStyle<Value>` + `.attributed` | :19881 / :20134 | macOS 12 / iOS 15 / tvOS 15 / watchOS 8 |
| `NumberFormatStyleConfiguration` | :20238 | macOS 12 / iOS 15 / tvOS 15 / watchOS 8 |
| `CurrencyFormatStyleConfiguration` (`.Notation` = macOS 15 / iOS 18 / tvOS 18 / watchOS 11) | :20342 | macOS 12 / iOS 15 / tvOS 15 / watchOS 8 |
| `ByteCountFormatStyle` + `.attributed` | :20433 / :20454 | macOS 12 / iOS 15 / tvOS 15 / watchOS 8 |
| `ListFormatStyle<Style,Base>` (`.list(memberStyle:type:width:)`) | :20825 / :20893 | macOS 12 / iOS 15 / tvOS 15 / **watchOS 8** *(CORRECTED — was wrongly watchOS 9)* |
| `PersonNameComponents.FormatStyle` + `.AttributedStyle` | :23071 / :23104 | macOS 12 / iOS 15 / tvOS 15 / watchOS 8 |
| `Measurement<UnitType>.FormatStyle` (UnitType: Dimension) | :16522 | macOS 12 / iOS 15 / tvOS 15 / watchOS 8 |
| `URL.FormatStyle` | :16182 | macOS 13 / iOS 16 / tvOS 16 / watchOS 9 |
| `Swift.Duration.TimeFormatStyle` / `.UnitsFormatStyle` | :20559 / :20666 | macOS 13 / iOS 16 / tvOS 16 / watchOS 9 |
| `Date.formatted<F>(_:)` | :2195 | macOS 12 / iOS 15 / tvOS 15 / watchOS 8 |
| `DateComponents.formatted<F>(_:)` + `init(_:strategy:)` | :2201 | **macOS 26 / iOS 26 / tvOS 26 / watchOS 26 / visionOS 26** ⚠️ |
| `DateComponents.ISO8601FormatStyle` + `.iso8601` | ~:8390 | **macOS 26 / iOS 26 / tvOS 26 / watchOS 26 / visionOS 26** ⚠️ *(added — research had missed this sibling)* |

The only **at-floor** (OS 26) APIs in the DateComponents formatting family are `DateComponents.formatted(_:)` / `init(_:strategy:)` and the `DateComponents.ISO8601FormatStyle` + `.iso8601` static. Per the versioning rule ([[nebula-spm-architecture]]), `since Nebula 26 == @available(iOS 26, *)` — gate them explicitly and document as a Nebula-26 addition. Everything else is below floor and unguarded.

`AttributedString` (and the `.attributed` variants) is `Sendable` and available iOS 15 / macOS 12 ([FormatStyle](https://developer.apple.com/documentation/foundation/formatstyle)), so attributed output is a first-class path.

### What we do NOT use (legacy Cocoa formatters)

`NumberFormatter`, `DateFormatter`, `ByteCountFormatter`, `ListFormatter`, `MeasurementFormatter`, `ISO8601DateFormatter` are non-`Sendable`, mutable, thread-unsafe, and **superseded in spirit** (not formally `@available(*, deprecated)` — no such annotation exists in the SDK) by the `FormatStyle` family. Nebula exposes only the modern types; wrappers around legacy formatters (if ever needed for a missing edge case) must be `@available(*, deprecated, message:)` and isolated. See [[nebula-date-time-extensions]] and [[nebula-number-measurement-extensions]] for the per-type extension story.

## Ground truth: Clock / Instant / Duration (_Concurrency)

`Clock`, `InstantProtocol`, `DurationProtocol`, `Duration`, `ContinuousClock`, `SuspendingClock` are Swift stdlib (_Concurrency module, present only as a prebuilt binary `.swiftmodule` under `.../usr/lib/swift/*/prebuilt-modules/27.0/_Concurrency.swiftmodule` — no textual `.swiftinterface`), introduced in Swift 5.7 ([SE-0329](https://github.com/apple/swift-evolution/blob/main/proposals/0329-clock-instant-duration.md)). Platform availability (per Apple docs + [Meet Swift Async Algorithms, WWDC22 110355](https://developer.apple.com/videos/play/wwdc2022/110355/)):

| Type | iOS | macOS | tvOS | watchOS | visionOS |
|---|---|---|---|---|---|
| `Clock`, `Instant`, `Duration`, `ContinuousClock`, `SuspendingClock` | 16.0 | 13.0 | 16.0 | 9.0 | 1.0 |

All below the .v26 floor. Key APIs:

- `Clock.now: Instant`, `Clock.minimumResolution: Duration`, `func sleep(until:tolerance:) async throws -> SleepResult`
- `extension Clock { func measure<T>(_ work: () async throws -> T) async rethrows -> (T, Duration) }` — the basis for `NebulaMeasure.measure`.
- `Duration.seconds(_:)/milliseconds(_:)/nanoseconds(_:)/microseconds(_:)` (Int and Double), `var components: (seconds: Int64, attoseconds: Int64)`, arithmetic operators.
- **ContinuousClock** advances during system sleep (wall-clock; WWDC22 recommends it for human-relative durations); **SuspendingClock** suspends with the process.

There is **no** `Foundation.Duration` — [developer.apple.com/documentation/foundation/duration](https://developer.apple.com/documentation/foundation/duration) 404s. `Duration` is `Swift.Duration` (`_Concurrency`); formatting is via `Swift.Duration.TimeFormatStyle` / `UnitsFormatStyle` in Foundation (`.swiftinterface` :20559 / :20666, as `extension Swift::Duration`). Nebula uses `Swift.Duration` exclusively. **There is no top-level `Duration.Unit`** — the unit type is `Duration.UnitsFormatStyle.Unit`, and `UnitsFormatStyle.init` takes `Set<Duration.UnitsFormatStyle.Unit>` (plus `width`, `maximumUnitCount`, `zeroValueUnits`, `valueLength`, `fractionalPart`).

## Ground truth: os signposts (OSSignposter)

`OSLog` is a clang module (`framework module OSLog [system] { umbrella header "OSLog.h"; export * }`); there is **no** textual `.swiftinterface` in the Xcode 27 Beta.3 toolchain (only prebuilt binary `.swiftmodule`). API surface taken from [Apple's OSSignposter docs](https://developer.apple.com/documentation/os/ossignposter) + [WWDC20 10168 Explore logging in Swift](https://developer.apple.com/videos/play/wwdc2020/10168/) + [WWDC18 405 Measuring Performance Using Logging](https://developer.apple.com/videos/play/wwdc2018/405/):

```swift
protocol OSSignposter {           // iOS 15 / macOS 12 / tvOS 15 / watchOS 8 / visionOS 1
    var logHandle: OSLog { get }
    var signpostLogHandle: OSLog { get }
    func makeSignpostID() -> OSSignpostID
    func beginInterval(_ signpostType: OSLogSignpostType, name: StaticString) -> OSSignpostIntervalState
    func beginInterval(_ id: OSSignpostID, name: StaticString) -> OSSignpostIntervalState
    func endInterval(_ name: StaticString, state: OSSignpostIntervalState)
    func emitEvent(_ name: StaticString)
    func emitEvent(_ id: OSSignpostID, name: StaticString)
}
enum OSLogSignpostType: UInt8 { case event, begin, end }
struct OSSignpostIntervalState; struct OSSignpostID
extension Logger {
    func signpost(_ signpostType: OSLogSignpostType, name: StaticString)
    func signpost(_ signpostType: OSLogSignpostType, name: StaticString, id: OSSignpostID)
}
```

All below the .v26 floor. Signpost names are `StaticString` (Apple requirement) — Nebula's API mirrors that; dynamic labels use `OSSignpostID` + `emitEvent` with a fixed category. `Logger(subsystem:category:)` ([os.Logger](https://developer.apple.com/documentation/os/logger), iOS 14 / macOS 11) provides a `.signposter` accessor; `NebulaSignposter` is built from the same `subsystem` + `category` used by [[nebula-logging]] so measure intervals and log atoms share an Instruments trace.

## Recommended design for Nebula

### Module placement (single SPM target `Nebula`)

```
Sources/Nebula/
  Formatting/NebulaStandards.swift
  Formatting/NebulaStandards+Builders.swift
  Measure/NebulaMeasure.swift
  Measure/NebulaMeasureResult.swift
  Measure/NebulaSignposter.swift
```

### NebulaStandards (formatting facade)

A Sendable value struct holding `locale`/`timeZone`/`calendar`, with fluent `.with*` builders (mirroring the [[nebula-logging]] `NebulaLogConfiguration` / Cosmos `CosmosLogConfiguration` contract — but **without** SwiftUI `@Entry`/`@Observable`). It returns Apple's real `FormatStyle` values, pre-configured, so callers keep the full Apple API (`.attributed`, `.precision`, `.grouping`, `.locale`, `.notation`). Nebula does **not** re-wrap formatting behind an opaque `format(_:)` — it is a thin, non-reinventing facade.

```swift
public struct NebulaStandards: Sendable {
    public var locale: Locale
    public var timeZone: TimeZone
    public var calendar: Calendar
    public init(locale: Locale = .autoupdatingCurrent,
               timeZone: TimeZone = .autoupdatingCurrent,
               calendar: Calendar = .autoupdatingCurrent)
    public static let `default` = NebulaStandards()

    public func withLocale(_ l: Locale) -> Self
    public func withTimeZone(_ tz: TimeZone) -> Self
    public func withCalendar(_ c: Calendar) -> Self

    // typed accessors returning Apple FormatStyle (all Sendable, below floor unless noted)
    public var date: Date.FormatStyle { get }                              // macOS 12/iOS 15
    public var iso8601: Date.ISO8601FormatStyle { get }                      // macOS 12/iOS 15
    public func date(verbatim pattern: String) -> Date.VerbatimFormatStyle  // macOS 12/iOS 15
    public var decimal: Decimal.FormatStyle { get }                        // macOS 12/iOS 15
    public func integer<Value: BinaryInteger>() -> IntegerFormatStyle<Value>          // macOS 12/iOS 15
    public func double<Value: BinaryFloatingPoint>() -> FloatingPointFormatStyle<Value> // macOS 12/iOS 15
    public func percent<Value: BinaryFloatingPoint>() -> FloatingPointFormatStyle<Value>.Percent
    public func currency<Value: BinaryFloatingPoint>(code: String) -> FloatingPointFormatStyle<Value>.Currency
    public func byteCount(style: ByteCountFormatStyle.Style = .file) -> ByteCountFormatStyle  // macOS 12/iOS 15
    public func list<MemberStyle: FormatStyle, Base: Sequence>(                          // macOS 12/iOS 15 (CORRECTED)
        memberStyle: MemberStyle, type: ListFormatStyle<MemberStyle, Base>.ListType = .and,
        width: ListFormatStyle<MemberStyle, Base>.Width = .standard) -> ListFormatStyle<MemberStyle, Base>
    public var name: PersonNameComponents.FormatStyle { get }               // macOS 12/iOS 15
    // CORRECTED: no `unit` param — width/usage/numberFormatStyle; unit implied by Measurement<U>
    public func measurement<U: Dimension>(
        width: Measurement<U>.FormatStyle.UnitWidth = .abbreviated,
        usage: MeasurementFormatUnitUsage<U> = .general,
        numberFormatStyle: FloatingPointFormatStyle<Double>? = nil
    ) -> Measurement<U>.FormatStyle                                          // macOS 12/iOS 15
    // CORRECTED: Set<Duration.UnitsFormatStyle.Unit> (no top-level Duration.Unit); macOS 13/iOS 16/watchOS 9
    public func duration(units: Set<Duration.UnitsFormatStyle.Unit>,
                         width: Duration.UnitsFormatStyle.UnitWidth = .abbreviated,
                         maximumUnitCount: Int? = nil) -> Duration.UnitsFormatStyle
    public func duration(pattern: Duration.TimeFormatStyle.Pattern) -> Duration.TimeFormatStyle  // macOS 13/iOS 16/watchOS 9
    public var url: URL.FormatStyle { get }                                 // macOS 13/iOS 16/watchOS 9

    public func string<T>(_ value: T, format: some FormatStyle<T, String>) -> String
    public func attributed<T>(_ value: T, format: some FormatStyle<T, AttributedString>) -> AttributedString
    public func iso8601String(for date: Date, includingFractionalSeconds: Bool = false) -> String

    // AT-FLOOR (OS 26 / Nebula 26)
    @available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    public func string(_ components: DateComponents, format: some FormatStyle<DateComponents, String>) -> String
}
```

### NebulaMeasure + NebulaSignposter (measure subsystem)

```swift
public struct NebulaMeasure: Sendable {
    public var clock: any Clock<Duration>           // default: ContinuousClock (iOS 16/macOS 13)
    public var signposter: NebulaSignposter?        // nil disables signposts
    public init(clock: any Clock<Duration> = ContinuousClock(),
                signposter: NebulaSignposter? = .default)
    public static let `default` = NebulaMeasure()

    public func measure<T>(_ name: StaticString, operation: () throws -> T) rethrows -> (T, Duration)
    public func measure<T>(_ name: StaticString, operation: () async throws -> T) async rethrows -> (T, Duration)
    public func bench(_ name: StaticString, iterations: Int, warmup: Int = 0,
                      operation: () throws -> Void) rethrows -> NebulaMeasureResult
}

public struct NebulaMeasureResult: Sendable {
    public let name: String
    public let iterations: Int
    public let total: Duration
    public var perIteration: Duration { total / iterations }
    public var components: (seconds: Int64, attoseconds: Int64) { total.components }
}

public struct NebulaSignposter: Sendable {
    public let subsystem: String
    public let category: String
    public init(subsystem: String, category: String = "Nebula.Measure")
    public static let `default`: NebulaSignposter?     // from Logger(subsystem:category:).signposter
    public func interval<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T
    public func interval<T>(_ name: StaticString, _ body: () async throws -> T) async rethrows -> T
    public func event(_ name: StaticString)
    public func makeID() -> OSSignpostID
}
```

`NebulaMeasure.measure` runs the op under `Clock.measure` **and** (if `signposter != nil`) wraps it in `OSSignposter.beginInterval(.begin, name:)` / `endInterval(.end, name:)`, so the same run appears in Instruments and yields a `Duration`. `bench` does `warmup` + `iterations` synchronous runs and returns `NebulaMeasureResult`. Default clock is `ContinuousClock` (wall-clock, advances during sleep — WWDC22 recommendation for human-relative durations).

### Public API surface (symbol / kind / purpose)

| Symbol | Kind | Purpose |
|---|---|---|
| `NebulaStandards` | `public struct (Sendable)` | Formatting facade: holds locale/tz/calendar; returns Apple `FormatStyle` values + `.with*` builders; `static .default`. |
| `NebulaStandards.date` / `.iso8601` / `.decimal` / `.name` / `.url` | properties → `FormatStyle` | Configured modern formatters (below floor). |
| `NebulaStandards.date(verbatim:)` | method → `Date.VerbatimFormatStyle` | Fixed-pattern date formatting (macOS 12/iOS 15). |
| `NebulaStandards.integer<Value>()` / `.double<Value>()` | methods → `IntegerFormatStyle` / `FloatingPointFormatStyle` | Generic numeric formatting. |
| `NebulaStandards.percent<Value>()` / `.currency<Value>(code:)` | methods → `.Percent` / `.Currency` | Percent/currency notation. |
| `NebulaStandards.byteCount(style:)` | method → `ByteCountFormatStyle` | Replaces `ByteCountFormatter`. |
| `NebulaStandards.list(memberStyle:type:width:)` | method → `ListFormatStyle` | List formatting over `Sequence` (CORRECTED: macOS 12/iOS 15/watchOS 8). |
| `NebulaStandards.measurement<U>(width:usage:numberFormatStyle:)` | method → `Measurement<U>.FormatStyle` | Measurement formatting (CORRECTED: no `unit` param). |
| `NebulaStandards.duration(units:width:maximumUnitCount:)` | method → `Duration.UnitsFormatStyle` | Format `Swift.Duration` (CORRECTED: `Set<Duration.UnitsFormatStyle.Unit>`, macOS 13/iOS 16/watchOS 9). |
| `NebulaStandards.duration(pattern:)` | method → `Duration.TimeFormatStyle` | Format `Swift.Duration` as time pattern (macOS 13/iOS 16/watchOS 9). |
| `NebulaStandards.string(_:format:)` / `.attributed(_:format:)` | methods → `String` / `AttributedString` | Convenience entry points. |
| `NebulaStandards.string(_:format:)` (DateComponents) | method, `@available(iOS 26, *)` | **At-floor** date-components formatting (OS 26). |
| `NebulaMeasure` | `public struct (Sendable)` | Timing helper over `any Clock<Duration>`; `measure`/`bench`. |
| `NebulaMeasure.measure(_:operation:)` | method → `(T, Duration)` (sync + async) | Op under `Clock.measure` + signpost interval. |
| `NebulaMeasure.bench(_:iterations:warmup:operation:)` | method → `NebulaMeasureResult` | Micro-benchmark. |
| `NebulaMeasureResult` | `public struct (Sendable)` | `name`/`iterations`/`total`/`perIteration`/`components`. |
| `NebulaSignposter` | `public struct (Sendable)` | Wraps `OSSignposter`; `interval(_:body:)`/`event(_:)`/`makeID()`. |
| `NebulaStandards.withLocale/.withTimeZone/.withCalendar` | methods → `Self` | Fluent builders (Cosmos contract minus SwiftUI). |

## Apple patterns adopted

- Prefer modern `FormatStyle` (Date, Decimal, Integer, FloatingPoint, ByteCount, List, PersonNameComponents, Measurement, URL, Duration) over legacy `NumberFormatter`/`DateFormatter`/`ByteCountFormatter`/`ListFormatter`/`MeasurementFormatter`/`ISO8601DateFormatter` — all `Sendable`, locale-fluent, below floor. (Legacy formatters are superseded in spirit, not formally `@deprecated` in the SDK.)
- `AttributedString` as first-class output via `.attributed` / `AttributedStyle` (`AttributedString` is `Sendable`, iOS 15 / macOS 12) — no `NSAttributedString`.
- `Clock`/`Instant`/`Duration` (`_Concurrency`, Swift 5.7) + `clock.measure(_:)` for timing instead of `CFAbsoluteTime`/`Date`/`ProcessInfo`; `ContinuousClock` as wall-clock default ([WWDC22 110355](https://developer.apple.com/videos/play/wwdc2022/110355/)).
- `OSSignposter` + `Logger.signpost` for Instruments ([Apple OSSignposter docs](https://developer.apple.com/documentation/os/ossignposter), [WWDC20 10168](https://developer.apple.com/videos/play/wwdc2020/10168/), [WWDC18 405](https://developer.apple.com/videos/play/wwdc2018/405/)), not the C `os_signpost` macro.
- Sendable value-struct configuration + fluent `.with*` builders mirroring `CosmosLogConfiguration` ([nebula-logging]) — minus SwiftUI `@Entry`/`@Observable`.
- Gate OS-introduced features with `@available`; API availability == versioning (`since Nebula 26` == `@available(iOS 26, *)`) — see [[nebula-spm-architecture]].
- No `NSLock`/`DispatchQueue`/`nonisolated(unsafe)`; this subsystem has no shared mutable state (results are per-call values), so `Mutex<T>`/`Atomic<T>` (`import Synchronization`, Swift 6.0) is **not** needed here — reserved for [[nebula-swift6-concurrency]] if a shared counter is ever introduced.
- `StaticString` for signpost names (Apple requirement); dynamic names via `OSSignpostID` + `emitEvent`.
- Derived `Sendable` conformance everywhere; closures `@Sendable` only when escaping (measure does not escape sync closures).

## Risks & open questions

### Risks

- **`DateComponents.formatted(_:)` is OS 26-only** (`.swiftinterface:2201`, `@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)`). At-floor (Nebula 26 == OS 26), so allowed, but MUST be `@available(iOS 26, *)`-gated; an unguarded reference will fail to compile against the `.v26` deployment target. Document as `since Nebula 26`. The sibling `DateComponents.ISO8601FormatStyle` + `.iso8601` static (interface ~8390) is ALSO OS 26 — gate it too if ever exposed.
- **CORRECTED: `ListFormatStyle` is macOS 12/iOS 15/watchOS 8** (interface:20823/20892), the same floor as the core family — NOT macOS 13/iOS 16/watchOS 9 as originally claimed. The watchOS-9-requiring APIs in scope are `URL.FormatStyle`, `Duration.TimeFormatStyle`/`UnitsFormatStyle`, and `Clock`/`Duration`. If Nebula ever lowers its deployment target below watchOS 9, re-gate those — but not `ListFormatStyle`.
- **Signpost name is `StaticString`** — no interpolation. `NebulaSignposter` takes `StaticString`; dynamic labels need `OSSignpostID` + `emitEvent` with a constant category name.
- **OSLog has no textual `.swiftinterface`** in this toolchain (clang module, binary-only `.swiftmodule`). `OSSignposter`/`Logger.signpost` availability (iOS 15 / macOS 12 / tvOS 15 / watchOS 8 / visionOS 1) is from Apple docs + WWDC, slightly weaker ground truth than the Foundation `.swiftinterface` (the docs page rendered only its title to a WebFetch, so availability rests on Apple's published table + WWDC). Mitigation: keep `NebulaSignposter` thin and matching Apple's documented protocol.
- **CORRECTED signature risks:** (a) There is **no** top-level `Duration.Unit` — the unit type is `Duration.UnitsFormatStyle.Unit`, and `UnitsFormatStyle.init` takes `Set<Duration.UnitsFormatStyle.Unit>` plus `width`/`maximumUnitCount`/`zeroValueUnits`/`valueLength`/`fractionalPart`, NOT an Array. (b) `Measurement<U>.FormatStyle` is constructed with `width`/`usage`/`numberFormatStyle`/`locale` — there is **no** `unit` parameter; the unit is implied by the `Measurement<U>` value being formatted. Nebula accessors must mirror these exact Apple shapes or they will not compile.
- **`CurrencyFormatStyleConfiguration.Notation`** is macOS 15 / iOS 18 / tvOS 18 / watchOS 11 (re-gated typealias inside `CurrencyFormatStyleConfiguration`) — below .v26, safe, but the only sub-API above watchOS 8 actually used in scope; `.notation(.scientific)` on currency needs the higher floor.
- **Legacy formatters are not formally deprecated** — no `@available(*, deprecated)` annotation exists in `Foundation.swiftinterface` for `NumberFormatter`/`DateFormatter`/`ByteCountFormatter`/`ListFormatter`/`MeasurementFormatter`/`ISO8601DateFormatter`. They are superseded in spirit (non-Sendable, mutable) by the `FormatStyle` family; Nebula docs should say "superseded / avoid" rather than "deprecated".
- **No `Foundation.Duration`** ([developer.apple.com/documentation/foundation/duration](https://developer.apple.com/documentation/foundation/duration) 404s). Use `Swift.Duration` everywhere; formatting via `Swift.Duration.TimeFormatStyle`/`UnitsFormatStyle` in Foundation.
- **ContinuousClock vs SuspendingClock** changes benchmark numbers (ContinuousClock counts sleep, SuspendingClock does not — [WWDC22 110355](https://developer.apple.com/videos/play/wwdc2022/110355/)). Document the default; expose `NebulaMeasure(clock: SuspendingClock())` for machine-relative timing.
- **`bench()` is not statistically rigorous** — no p50/p99, no clock-resolution check; runs on the caller's thread. Document as a quick micro-bench.

### Open questions

- Should `NebulaMeasureResult` include distribution stats (min/max/mean/p50/p99) + `Clock.minimumResolution`, or stay minimal for v1?
- Should `NebulaStandards` expose a polymorphic `.format(_ value:)`, or only typed accessors (current — preserves full Apple API + `AttributedString` variants)?
- Should `NebulaSignposter.default` be enabled or nil-by-default in release builds (signposts always-on vs opt-in)? Consider a `#if DEBUG` default or a release disable flag on [[nebula-logging]]'s `NebulaLogConfiguration`.
- Should `NebulaStandards` be passed around or used as `NebulaStandards.default.date`? (Mirror Cosmos `static .default`; allow per-module instance for testability.)
- Type-erased `AnyFormatStyle` / `NebulaStandards.FormatStyle` alias for helpers that store "some format" generically, or is generic `<F: FormatStyle>` enough?
- Distinct `measureSuspending` API, or just `NebulaMeasure(clock: SuspendingClock())`?
- Should `bench()` auto-detect `minimumResolution` and warn if `iterations × per-op < minimumResolution` (unreliable)?
- Should Nebula also expose the OS-26 `DateComponents.ISO8601FormatStyle` (interface ~8390) alongside `DateComponents.formatted(_:)`, gated `@available(iOS 26, *)` — since the whole `DateComponents` formatting family is at-floor — or keep only the generic `formatted(_:)` accessor for v1?

## Shipped shape (Wave F — reconciles the design above with the code)

Wave F landed green (379 tests, zero concurrency warnings, release clean). The shipped types deviate from the "Recommended design" sketches above in three deliberate ways, all documented in source doc-comments:

1. **`NebulaMeasureConfiguration` is the 4th config struct AND the measure type** — the design above proposed a separate `NebulaMeasure` struct. To match the four-config-struct contract in [[CLAUDE]] and mirror `NebulaLogConfiguration` (which carries `log()` ON the config), `measure(_:_:)` / `bench(_:_:)` live ON `NebulaMeasureConfiguration`. No separate `NebulaMeasure` / `NebulaClock` types ship. Sendable ONLY, NOT `Equatable` (stores the `@Sendable` handler), mirroring `NebulaLogConfiguration`.
2. **`NebulaSignposter` is NOT duplicated** — the existing `Sources/Nebula/Logging/NebulaSignposter.swift` (Wave A) is reused as the `signposter: NebulaSignposter?` field. Its `osSignposter` accessor (concrete `os.OSSignposter`) is the escape hatch for `beginInterval`/`endInterval`/`withIntervalSignpost`. The design-above `interval(_:body:)`/`event(_:)`/`makeID()` wrappers were NOT added (would require editing the stable Logging file; `.osSignposter` is sufficient).
3. **`NebulaStandards` carries NO handler** — the only one of the four config structs without a `@Sendable` closure, because formatting is stateless (no fan-out path).

### Two `OSSignposter`/`Clock` facts corrected against the Xcode 27 Beta 3 / Swift 6.4 toolchain (verified with `xcrun swiftc` scratch tests)

- **`Clock.measure` returns ONLY `Duration`** (there is NO `(T, Duration)` tuple form, sync or async). `NebulaMeasureConfiguration.measure(_:_:)` captures the result inside the closure body: `try clock.measure { result = try op() }` (sync), `try await clock.measure { () async throws -> Void in … result = try await op() }` (async). The async `measure` body is explicitly annotated `() async throws -> Void` because the async overload requires a Void body (a body returning `T` resolves to the wrong overload).
- **`OSSignposter.withIntervalSignpost` has NO async variant.** The sync `measure` wraps the op in `sp.withIntervalSignpost(name) { try op() }` (works — forwarding a `StaticString` `name` compiles and runs; the existing `NebulaSignposter.swift` "forwarding fails" comment is over-conservative and applies to `SignpostMetadata`/`OSLogMessage` messages, not the `name`). The async `measure` uses manual `sp.beginInterval(name)` / `defer { sp.endInterval(name, state) }` because `withIntervalSignpost` cannot take an async body.

### Other shipped details

- `NebulaMeasureResult.perIteration` uses `total / iterations` (Int division — `Duration / Int` exists and preserves seconds+attoseconds; `Duration / Double` also exists). `NebulaMeasureResult: Sendable, Equatable` (derived; synthesized `==` compares only the stored `name`/`iterations`/`total`).
- `bench(_:_:)`'s `name: StaticString` → `String(describing: name)` (there is no lossless `String(_:)` for `StaticString`).
- `NebulaStandards.date` uses the `Date.FormatStyle(date:time:locale:calendar:timeZone:)` init, NOT `.dateTime.locale().timeZone().calendar()`: `Date.FormatStyle` has no `.calendar(_:)` builder, and `.timeZone(_:)` takes a `Date.FormatStyle.Symbol.TimeZone` display enum (not a `TimeZone`). ISO8601 mirrors `NebulaDateFormat.iso8601(timeZone:)` (`.omitted` for GMT, `.colon` otherwise).
- Generic `string<T>(_:format:)` / `attributed<T>(_:format:)` call `format.format(value)` (the `FormatStyle` protocol requirement), NOT `value.formatted(format)` — there is no universal `formatted(_:)` on arbitrary values.
- No-arg `string(_ components: DateComponents)` uses `DateComponents.ISO8601FormatStyle.iso8601` (at-floor, interface ~8396) as the canonical default — `DateComponents` has no no-arg `formatted()`.
- `default` signposter is `nil` (opt-in signposts — a foundation should not force Instruments overhead by default). `default` clock is `ContinuousClock()` (wall-clock).
- Process-wide accessors `NebulaStandardsConfig` / `NebulaMeasureConfig` mirror `NebulaLogConfig` / `NebulaErrorConfig` (`Mutex<T>` from `Synchronization`, `let` never `var`).
- No `@unchecked Sendable` authored on any Nebula type (verified by grep). No UIKit, no `#if os`/`#if canImport` in the new modules (everything below-floor except the two `DateComponents` accessors, gated `@available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)`).

## Sources

- [FormatStyle — Apple Developer Documentation](https://developer.apple.com/documentation/foundation/formatstyle)
- [Date.FormatStyle — Apple Developer Documentation](https://developer.apple.com/documentation/foundation/date/formatstyle)
- [IntegerFormatStyle — Apple Developer Documentation](https://developer.apple.com/documentation/foundation/integerformatstyle)
- [Measurement / Measurement.FormatStyle — Apple Developer Documentation](https://developer.apple.com/documentation/foundation/measurement)
- [ByteCountFormatStyle — Apple Developer Documentation](https://developer.apple.com/documentation/foundation/bytecountformatstyle)
- [ListFormatStyle — Apple Developer Documentation](https://developer.apple.com/documentation/foundation/listformatstyle)
- [PersonNameComponents.FormatStyle — Apple Developer Documentation](https://developer.apple.com/documentation/foundation/personnamecomponents/formatstyle)
- [Duration.TimeFormatStyle — Apple Developer Documentation](https://developer.apple.com/documentation/foundation/duration/timeformatstyle)
- [Clock — Apple Developer Documentation](https://developer.apple.com/documentation/swift/clock)
- [Meet Swift Async Algorithms — WWDC22 session 110355](https://developer.apple.com/videos/play/wwdc2022/110355/)
- [OSSignposter — Apple Developer Documentation](https://developer.apple.com/documentation/os/ossignposter)
- [Logger.signpost(_:name:) — Apple Developer Documentation](https://developer.apple.com/documentation/os/logger/signpost(_:name:))
- [Explore Logging in Swift — WWDC20 session 10168](https://developer.apple.com/videos/play/wwdc2020/10168/)
- [Measuring Performance Using Logging — WWDC18 session 405](https://developer.apple.com/videos/play/wwdc2018/405/)
- [os Logging overview — Apple Developer Documentation](https://developer.apple.com/documentation/os/logging)
- [SE-0329 Clock, Instant, Duration](https://github.com/apple/swift-evolution/blob/main/proposals/0329-clock-instant-duration.md)
- [SE-0302 Sendable / @Sendable closures](https://github.com/apple/swift-evolution/blob/main/proposals/0302-sendable.md)
- [SE-0410 Atomics / Synchronization (Mutex, Atomic)](https://github.com/apple/swift-evolution/blob/main/proposals/0410-atomics.md)
- Foundation.swiftinterface (arm64e-apple-macos, MacOSX27.0.sdk) — `/Applications/Xcode-27.0.0-Beta.3.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/Foundation.framework/Versions/C/Modules/Foundation.swiftmodule/arm64e-apple-macos.swiftinterface` (lines :8471, :8202, :8296, :18437, :19104, :19389, :19637, :19881, :20238, :20342, :20433, :20825, :20892, :23071, :16522, :16608, :16182, :20550, :20559, :20666, :2195, :2201, ~8390)
- OSLog module.modulemap — `/Applications/Xcode-27.0.0-Beta.3.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/OSLog.framework/Modules/module.modulemap`
- _Concurrency / Synchronization prebuilt binary .swiftmodule — `/Applications/Xcode-27.0.0-Beta.3.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/{macosx,iphoneos,...}/prebuilt-modules/27.0/{_Concurrency,Synchronization}.swiftmodule`
- Cosmos sibling reference — `/Users/rafael.escaleira/Documents/projects/personal/cosmos/Sources/Cosmos/Base/Configuration/CosmosLogConfiguration.swift`

Source of truth = root docs (CLAUDE.md, ARCHITECTURE.md, DECISIONS.md, VERSIONING.md); this note is the synthesis. On conflict, the root doc wins.
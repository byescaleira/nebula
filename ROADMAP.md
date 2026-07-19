# Roadmap

> Last updated: 2026-07-19 (Wave H — Clean Architecture toolkit shipped. Waves A–H shipped; 509 tests green.)
>
> This roadmap reflects the project state **after the foundation research cycle** that produced
> the 12 verified research dimensions. The vault notes (`01-fundamentos/` + `03-padroes/`) are the
> synthesis layer; the root docs (`ARCHITECTURE.md`, `DECISIONS.md`, `VERSIONING.md`, `CLAUDE.md`)
> are the source of truth.

## Done (0.1.0 — first complete foundation release)

### Wave A — Package scaffold + governance + vault
- [x] Bootstrap SPM package `Nebula` for Apple v26 platforms (iOS / macOS / tvOS / watchOS / visionOS, all `.v26`)
- [x] `swift-tools-version: 6.3` (dual Xcode 26.4+ / Xcode 27 build); `swiftLanguageModes: [.v6]`; `defaultLocalization: "en"`
- [x] Single `Nebula` target + `NebulaTests` (Swift Testing); no third-party dependencies; `.process("Resources")` commented (foundation emits developer-facing English; no String Catalog by default)
- [x] `Sources/Nebula/` folder tree: `Nebula.swift` (top-level `Nebula` enum + `NebulaVersion`), `Logging/`, `Errors/`, `Extensions/{DateTime,String,Number,Primitive,Collection,Codable,DataURL}/`, `Standardize/`, `Measure/`, `Nebula.docc/` (no `Core/`, `Concurrency/`, or `Formatting/` dirs — those planned subdirs were not shipped; `NebulaVersion` lives in the top-level `Nebula.swift`, and there is no `NebulaLocked`/`NebulaFlag`/`NebulaOnce` concurrency wrapper layer)
- [x] `NebulaVersion` (in `Nebula.swift` — Nebula N == OS N baseline; `static let version = NebulaVersion(major: 26, minor: 0, patch: 0)`)
- [x] Governance docs: `CLAUDE.md`, `ARCHITECTURE.md`, `DECISIONS.md`, `VERSIONING.md`, `ROADMAP.md`, `CONTRIBUTING.md`, `PROPOSAL.md`, `README.md`, `CHANGELOG.md`
- [x] Obsidian vault MOC (`vault/Home.md`) + 12 research notes across `01-fundamentos/` (10) and `03-padroes/` (2: `nebula-spm-architecture`, `nebula-swift6-concurrency`)

### Wave B — Logging + signposts — DONE
- [x] Shipped: `NebulaLogLevel`, `NebulaLogCategory`, `NebulaLogger` (Sendable struct over `os.Logger`; exposes `osLogger` for the redaction-preserving `OSLogMessage` path and `String` convenience level methods for the simple path — `os.Logger` cannot be wrapped, verified), `NebulaLogEvent`, `NebulaLogConfiguration` (+ `NebulaLogConfig` process-wide `Mutex` accessor), `NebulaSignposter`/`NebulaSignpostID`/`NebulaSignpostIntervalState`/`NebulaSignpostMetadata` (typealias = `os.SignpostMetadata`), `NebulaMemoryLogHandler` (`final class @unchecked Sendable`, `Mutex<T>`-backed ring buffer; test/preview-only).
- Deferred: `NebulaLogStoreExporter`/`NebulaLogStoreEntry` (macOS-only `.system`/`.local()` gated `#if os(macOS)` + explicit per-platform unavailable — NOT `@available(macOS 12, *)` alone) — moved to "Later".

### Wave C — Errors — DONE
- [x] Shipped: `NebulaError` (`Error`/`LocalizedError`/`CustomNSError`/`Sendable`/`Hashable`) + `Code`/`Kind`/`Context`/`Box` (final class — struct recursion illegal); lossy mapping inits (`NSError`/`DecodingError`/`URLError`/`CocoaError`/`any Error`) + `EncodingError` bridge + `NebulaError.wrap(_:) -> Result<T, NebulaError>`; `NebulaErrorConfiguration` (Sendable ONLY — NOT `Equatable`) + `NebulaErrorEvent` (Sendable + Equatable) + fluent `.with*`; `NebulaErrorConfig` process-wide `Mutex<NebulaErrorConfiguration>` accessor; `NebulaDecodingError`/`NebulaEncodingError`.

### Wave D — Extensions batch 1 — DONE
- [x] Shipped (Extensions/DateTime): `Date` arithmetic/predicates (DST-safe via `calendar.dateInterval(of:for:)`); `DateComponents` builders; `DateInterval.init(start:duration: Swift.Duration)`; `NebulaDateFormat`/`NebulaDurationFormat` façades. ISO/stable presets pinned to `Locale(identifier: "en_US_POSIX")` + `.gmt`. No `NebulaClock` (deferred).
- [x] Shipped (Extensions/String): `isBlank`/`nilIfEmpty`/`trimmed`/`truncated(to:with:)`/case conversions/base64/hex/URL extraction; `NebulaRegex<Output>` (Sendable, conditional `where Output: Sendable`); `NebulaRegexPatterns` (curated literals — UUID/IPv4/hex/semver/ISO-timestamp; NO email); `NebulaStringDetectedEntity` over `NSDataDetector` (cached in `Mutex<NSDataDetector?>`); `NebulaStringLocalization` (Foundation scope only).
- [x] Shipped (Extensions/Primitive): `Comparable.clamped(to:)`; `BinaryInteger.isEven`/`isOdd`/`times(_:)`; `Optional.or(_:)`/`orThrow(_:)`/`isNilOrEmpty`; `NebulaNilError`; `UUID.shortString`/`isValid(_:)`; `UUID.random(using:)` gated `@available(iOS 26.4, *)`.
- [x] Shipped (Extensions/Collection): `nebulaChunked`/`nebulaWindows`/`nebulaUniqued`/`nebulaStablePartition`/`nebulaPartitioned`/`nebulaSorted`/`nebulaMerging`. `nebula*` prefix; eager by default; non-escaping `rethrows`. (`nebulaFiltered(by:)` + `NebulaFrequency` were deferred — see "Later".)
- [x] Shipped above-floor 26.4 gates: `Data.Base64EncodingOptions.base64URLAlphabet`/`.omitPaddingCharacter`, `String.Encoding.ianaName` getter AND `init?(ianaName:)`, `UUID.random(using:)`.

### Wave E — Extensions batch 2 — DONE
- [x] Shipped (Extensions/Number): `NebulaFormattingOptions` (Sendable + `.with*`); `NebulaNumberFormatting` façade (percent/currency/bytes/list/measurement — no legacy Formatter subclasses; `ListFormatter` per-call only); `BinaryInteger`/`BinaryFloatingPoint`/`Decimal` extensions; `Decimal.rounded(toDecimalPlaces:)` via `NSDecimalRound` + `NebulaDecimalRoundingRule` enum.
- [x] Shipped (Extensions/Codable): `NebulaJSONDecoder`/`NebulaJSONEncoder` (Sendable wrappers holding configure-once-frozen `JSONDecoder`/`JSONEncoder` in a `let`); `NebulaJSONDecoderConfiguration`/`NebulaJSONEncoderConfiguration` (Sendable + `.with*`); `Decodable.init(fromJSON:)`/`Encodable.toJSONData`/`toJSONString`/`Data.asPrettyJSONString`. No `OutputFormatting.fragmentsAllowed` (does not exist).
- [x] Shipped (Extensions/DataURL): `Data.nebulaHexEncodedString`/`init?(nebulaHexEncoded:)`; `NebulaHashAlgorithm` (Sendable enum over CryptoKit SHA256/384/512 — the ONLY `import CryptoKit`); `Data.nebulaDigest`/`nebulaHexDigest`; `URL.nebulaAppending(queryItem:)`/`nebulaSettingQueryItem`/`nebulaRemovingQueryItem`/`nebulaPercentEncoded()`; `URLComponents.nebulaWith(queryItem:)`. base64URL/omitPadding gated at Nebula 26.4.

### Wave F — Standardize + Measure — DONE
- [x] Shipped (Standardize): `NebulaStandards` (formatting façade over `FormatStyle` family; `.withLocale`/`.withTimeZone`/`.withCalendar`; typed accessors only — no polymorphic `.format(_:)`) + `NebulaStandardsConfig` (process-wide `Mutex` accessor). DateComponents accessors gated `@available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)`.
- [x] Shipped (Measure): `NebulaMeasureConfiguration` (the 4th config struct — carries `measure(_:operation:)`/`bench(_:iterations:warmup:operation:)` ON the config, mirroring `NebulaLogConfiguration.log`; NO separate `NebulaMeasure` type) + `NebulaMeasureResult` (minimal: name/iterations/total/perIteration — no p50/p99 yet) + `NebulaMeasureConfig` (process-wide `Mutex` accessor). `NebulaSignposter` lives under Logging. No `NebulaClock` (deferred — measure uses `any Clock<Duration>` directly, default `ContinuousClock`).

### Wave G — DocC + CI + polish — DONE (tag pending)
- [x] DocC catalog articles at `Sources/Nebula/Nebula.docc/` (root `Nebula.md` + subsystem articles) — auto-discovered by SwiftPM
- [x] GitHub CI (`.github/workflows/ci.yml`) — 5-platform matrix (iOS/macOS/tvOS/watchOS/visionOS) + `swift build -c release` to exercise `#if os()` coverage; Xcode 26.4+ pinned
- [x] DocC generation via `xcodebuild docbuild` (no `swift-docc-plugin` — `Package.swift` keeps `dependencies: []` pristine)
- [x] README examples (logger + error + format) — corrected to the shipped API (`NebulaErrorConfig.report(error)`, redaction-preserving `logger.osLogger.info(...)` vs simple `logger.info(...)`)
- [x] Per-platform `#if os()` coverage pass — no `#if os(...)` in `Sources/` today (no platform-specific API shipped yet); the CI matrix is the forward-looking guard for when the deferred macOS-only `NebulaLogStoreExporter` lands
- [ ] Tag `0.1.0` — ready to tag (user action)

## Done (0.2.0 — Clean Architecture toolkit)

### Wave H — Clean Architecture toolkit — DONE
- [x] Shipped `Sources/Nebula/Architecture/` — the **second surface** of Nebula (foundation + architecture). Seams only — no presentation, DB, or framework code. Presentation patterns (MVVM/MVC/VIP/VIPER) explicitly out of scope; Cosmos is the presentation layer. Pure Swift + Foundation + `Synchronization`; every symbol at the Nebula 26 floor (no above-floor gates).
- [x] `Domain/` — `NebulaValue`/`NebulaEntity`/`NebulaAggregate` markers + `NebulaID<Entity>` phantom-typed UUID identity. 1-param (generic-parameter defaults rejected on this toolchain — verified `swiftc -parse`).
- [x] `Ports/` — bare `Sendable` markers `NebulaInputPort`/`NebulaOutputPort`/`NebulaDTO`.
- [x] `Errors/` — `NebulaFailure` protocol + per-layer open structs `NebulaDomainError`/`NebulaValidationError` (Equatable/Hashable derived) bridging to the closed `NebulaError.Kind` via caller-picked `toNebulaError(kind:)`. `NebulaError+Mapping.swift` dispatches `NebulaFailure` before the `NSError` fallback. No new `Kind` cases.
- [x] `UseCase/` — `NebulaUseCase<I, O>` generic `Sendable` struct + `NebulaUseCaseRole` (command/query) + `execute(_:)` (untyped `throws`) / `executeTyped(_:) async throws(NebulaError)` (SE-0413); `.logged`/`.measured`/`.reported`/`.instrumented` decorators route to the existing log/measure/error configs (no 5th config).
- [x] `Repository/` — PAT `NebulaRepository<Element>` + capability sub-protocols (read-only / keyed / writable / deletable); `stream()` returns concrete `AsyncThrowingStream` (`some AsyncSequence` illegal in a protocol requirement); `NebulaRepositoryError` (`Source` enum + open `Kind` + factory statics). No CRUD mandate, no `update` verb.
- [x] `Gateway/` — `NebulaGateway` marker + `NebulaGatewayConfiguration` (reuses `NebulaJSONDecoder`/`Encoder`) + `NebulaGatewayConfig` Mutex accessor. Concrete `NebulaHTTPGateway` deferred.
- [x] `Validation/` — `NebulaValidator<T>` (sync, short-circuit, `+`) + `NebulaAsyncValidator<T>` (async; a thrown I/O error propagates, NOT a `.failure`).
- [x] `Registry/` — `NebulaRegistryKey` (open struct) + `NebulaRegistryConfiguration` + `NebulaRegistry` (explicit injection) + `NebulaRegistryConfig` (process-wide Mutex). DI **without** a container.
- [x] `Testing/` — in-target test doubles `NebulaFakeRepository` / `NebulaStubUseCase` / `NebulaSpyUseCase` (`final class` + `let Mutex`; `Sendable` **derived** — final class with all-`let` `Sendable` properties, no `@unchecked`; the spy is explicitly `: Sendable` so it can be shared across tasks). Swift Testing `confirmation(expectedCount:)` for the spy.
- [x] `Async/` — `NebulaResultPipeline<T>` (`map`/`flatMap`/`recover` over `Result<T, NebulaError>`) + `AsyncSequence.nebulaChunked(byCount:)`/`nebulaUniqued(on:)`/`nebulaUniqued()`.
- [x] Tests — `ArchitectureDomainTests`/`PortsTests`/`ErrorsTests`/`UseCaseTests`/`RepositoryTests`/`GatewayTests`/`ValidationTests`/`RegistryTests`/`TestDoublesTests`/`AsyncFlowTests`. 509 tests / 107 suites green; zero concurrency warnings under Swift 6 mode (`rm -rf .build && swift build && swift test && swift build -c release`).
- [x] DocC — `Architecture.md` canonical article + 10 per-subsystem articles; linked from the module root.
- [x] Root docs — `ARCHITECTURE.md` (Architecture section), `DECISIONS.md` (Wave H ADR), `CHANGELOG.md` (0.2.0), `VERSIONING.md` (toolkit at-floor), this roadmap. Vault: 11 architecture notes marked shipped.
- [ ] Tag `0.2.0` — ready to tag (user action)

### Deferred (tracked below in "Later")
- `NebulaInvariant` (decision #6), `NebulaMockRepository` (#8), `NebulaHTTPGateway` (#8-resolved), `NebulaCancellation`/`NebulaError.wrapAsync` (#13), template multi-module product (#10).

## Later (post-0.1.0)

- [ ] `NebulaLogStoreExporter`/`NebulaLogStoreEntry` (deferred from Wave B) — macOS-only `.system`/`.local()` gated `#if os(macOS)` + explicit per-platform `@available(<platform>, unavailable)` (NOT `@available(macOS 12, *)` alone); `entries` copies into Sendable `NebulaLogStoreEntry` since `OSLogEntry` is not Sendable. visionOS availability uncertain → conservatively gate unavailable.
- [ ] `NebulaLocked<Value>`/`NebulaFlag`/`NebulaOnce` (`~Copyable`/`Sendable` concurrency wrappers around `Mutex`/`Atomic` — deferred from Wave A; compile-validate `~Copyable`+`Sendable` synthesis against the exact Swift 6.4 toolchain before shipping)
- [ ] `NebulaClock` (ContinuousClock/SuspendingClock wrapper; measure/now/sleep — deferred from Wave F; measure currently uses `any Clock<Duration>` directly)
- [ ] `NebulaMeasureResult` distribution stats (min/max/mean/p50/p99) + `Clock.minimumResolution` field
- [ ] `NebulaStandards.FormatStyle` polymorphic entry / `AnyFormatStyle` (if helpers need to store "some format" generically)
- [ ] `NebulaSignposter` default-disable in release builds (`#if DEBUG` default or release-build disable)
- [ ] OS 26 signpost-metric APIs — `NebulaMetricOperation` enum (add/subtract/set/reset) gated `@available(iOS 26, *)` (`OSMetricOperation` is internal to the os overlay — cannot re-export)
- [ ] Async `NebulaLogStoreExporter.entries` variant (sync `AnySequence` copying into `NebulaLogStoreEntry` for v1)
- [ ] `NebulaJSONSerialization` helper for top-level fragments
- [ ] `URLDetector` wrapper (NSDataDetector `.link` already in String extensions; defer standalone)
- [ ] `ValidatedCodable` wrapper / Codable validation helpers
- [ ] Back-deployment via `FoundationPreview` (if the floor ever lowers)
- [ ] `nebulaFiltered(by:)` (Foundation `Predicate`-based filter) + `NebulaFrequency` frequency-counter (deferred from Wave D — not shipped in 0.1.0; `nebulaFiltered`/`NebulaFrequency` referenced in early ROADMAP drafts were removed before tagging)
- [ ] `CountedSet` full API (if `NebulaFrequency` struct-copy is insufficient)
- [ ] Lazy sequence types behind `nebulaLazy` property (lazy needs `@escaping @Sendable` projections only there)

## Open risks / verification TODOs (verified at blueprint time, NOT now)

- visionOS availability of `OSLogStore.Scope.system`/`.local()` — header does NOT list visionOS in `API_UNAVAILABLE`; conservatively gate unavailable; confirm at compile time on the visionOS SDK.
- `~Copyable`+`Sendable` wrapper conformance synthesis for `NebulaLocked`/`NebulaFlag`/`NebulaOnce` — validate against the exact Swift 6.4 toolchain before scaffolding (the design matches verified stdlib signatures but synthesized `Sendable` for a `~Copyable` struct holding a `~Copyable` Sendable `let` was not executed in the research pass).
- watchOS/visionOS `FormatStyle` case differences — flag for Wave F verification against the `.swiftinterface` (DiscreteFormatStyle is iOS 18/watchOS 11 — below floor, ungated; but platform-specific case availability still needs enumeration).
- `_Concurrency` Clock/Instant/ContinuousClock/SuspendingClock ship only as binary prebuilt `.swiftmodule` (no textual `.swiftinterface`) — availability via Apple docs + SE-0329 + typecheck probe, not a local grep. Confirm at compile time.
- `OSLog` is a clang umbrella module with no textual `.swiftinterface` — `os.Logger`/`OSLogStore`/`OSLogEntry`/`OSSignposter` availability (iOS 14–15/macOS 11–12/tvOS 14–15/watchOS 7–8/visionOS 1, all below `.v26`) from Apple docs + WWDC; keep wrappers thin.
- CI Xcode pin: must be Xcode 26.4+ (Swift 6.3), not Xcode 26.0–26.3 (Swift 6.2, will NOT parse a 6.3 manifest).
- `WebFetch` has hallucinated availability tables repeatedly (UUID.random, percentEncodedQueryItems, `OutputFormatting.fragmentsAllowed`, `convertFromKebabCase`, `base64Encode`) — the `.swiftinterface` is authoritative; never rely on WebFetch for availability.

### Refuted specs / corrected citations (recorded in vault `08-riscos/`)

- `OSLogStore`/`OSLogEntry`/`getEntries` are NOT in `os.swiftmodule` (0 matches) — they live in the OSLog clang module + a separate `OSLog.swiftmodule` Swift overlay (getEntries at L11-14). The original `os.swiftmodule L11-14 getEntries` citation is wrong.
- `@available(macOS 12, *)` alone does NOT make a symbol macOS-only — the `*` fallback enables all platforms. Use `#if os(macOS)` or explicit per-platform `@available(<platform>, unavailable)`.
- `NebulaErrorConfiguration: Equatable` does NOT compile (`@Sendable` closure not `Equatable`) — corrected to Sendable only (mirrors `CosmosErrorConfiguration`).
- `underlying: NebulaError?` does NOT compile (struct recursion illegal) — corrected to `underlying: Box?` via `final class Box: Sendable, Hashable`.
- `Calendar.gregorian` does NOT exist as a static var → use `Calendar(identifier: .gregorian)`.
- `Date.RelativeFormatStyle` has NO `.offset`/`.timer`/parameterless `static var relative` — only `static func relative(presentation:unitsStyle:)`; timer-style display is `Duration.TimeFormatStyle.Pattern.hourMinuteSecond`. `RelativeFormatStyle` uses stored `var` properties + init, NOT a fluent chain.
- `Decimal` does NOT conform to `FloatingPoint`; `Decimal.FormatStyle` is its own struct. `Decimal` has NO value-level `rounded(_:)` — implement via `NSDecimalRound`.
- `ListFormatter` has NO `ItemStyle` enum (erroneous assumption in the brief).
- `UUID.random(using:)` (NOT parameterless `random()`) is `@available(iOS 26.4, *)` — ABOVE floor; `UUID()` remains the default random v4 generator.
- `JSONEncoder.OutputFormatting` has ONLY `prettyPrinted`/`sortedKeys`/`withoutEscapingSlashes` — NO `fragmentsAllowed` (that's `JSONSerialization.WritingOptions`); `ReadingOptions` uses `.allowFragments` (singular). NO `convertFromKebabCase`, NO `base64Encode`.
- Foundation has NO native hex encode/decode (grep confirms).
- `ListFormatStyle` + `.list` accessor are `@available(macOS 12, iOS 15, tvOS 15, watchOS 8)` — NOT macOS 13/iOS 16/watchOS 9 as originally claimed.
- `Duration` has NO top-level `Duration.Unit` — the unit type is `Duration.UnitsFormatStyle.Unit`, init takes a `Set`, NOT an `Array`.
- `Measurement<U>.FormatStyle` is constructed with `width`/`usage`/`numberFormatStyle`/`locale` — NO `unit` parameter.
- `DateComponents.ISO8601FormatStyle` + `.iso8601` static is ALSO OS 26 (research missed this) — gate alongside `DateComponents.formatted(_:)`.
- `swift-tools-version: 6.3` requires Xcode 26.4+ (Swift 6.3 first shipped in Xcode 26.4, March 2026); Xcode 26.0–26.3 shipped Swift 6.2.
- `Atomic.load(ordering:)` takes `AtomicLoadOrdering` (only `.relaxed`/`.acquiring`/`.sequentiallyConsistent`) — `.acquiringAndReleasing` is INVALID for `load` (lives in `AtomicUpdateOrdering`). NO single `Ordering` enum — three frozen structs.
- `Mutex.withLock` uses `sending` (SE-0430), NOT `transferring` (the earlier SE-0433 spelling was revised).
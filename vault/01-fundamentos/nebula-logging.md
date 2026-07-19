---
tags: [foundation, logging]
aliases: [nebula-logging, nebula-logger]
related: [[nebula-errors], [nebula-standardize-measure], [nebula-swift6-concurrency], [nebula-spm-architecture]]
---

# Nebula Logging Foundation

Nebula's logging subsystem is a thin `Sendable` facade over Apple's native unified-logging stack — `os.Logger`, `os.OSSignposter`, and `os.OSLogStore` — with **no third-party dependencies** (no `swift-log`, no custom backends). The binding constraint (see [[nebula-spm-architecture]]) mandates Apple frameworks only, so `os.Logger` is the ground-truth logging API and the Instruments/Console.app integration is free. This note verifies availability against the installed Xcode 27 Beta 3 SDK and proposes the public surface for `Sources/Nebula/Logging/`.

> **Verification note (adversarial re-check):** Several line/file citations in the original research were corrected. OSLogStore/OSLogEntry/getEntries live in the **OSLog clang module + a separate `OSLog.swiftmodule` Swift overlay**, NOT in `os.swiftmodule` (which contains 0 OSLogStore symbols). `Mutex<T>` requires iOS 18/macOS 15/visionOS 2.0 (not merely "Swift 6.0+"). `OSLogPrivacy.Mask.hash` is available macOS 11+/iOS 14+ (only `_mail*` cases are 12+/15+). visionOS availability of `OSLogStore.Scope.system`/`.local()` is **uncertain** (the header does not list visionOS in `API_UNAVAILABLE`). See "Corrections" below.

## Ground truth: where the API lives

`OSLog` is a **clang module** (`OSLog.framework/Modules/module.modulemap` → `umbrella header "OSLog.h"`), not a textual `.swiftinterface` in `Foundation.framework`. Two distinct Swift overlays ship as prebuilt `.swiftmodule` + textual `.swiftinterface` under each platform SDK at `usr/lib/swift/`:

- **`os.swiftmodule`** (2602 lines, `Apple Swift version 6.4 effective-5.10`) — holds `Logger`, `OSSignposter`, `OSLogType`, `OSLogPrivacy`, `OSSignpostID`, `SignpostMetadata`, `OSSignpostIntervalState`, `OSLog.Category`. Does `@_exported import os.log` / `os` / `os.signpost` / `os.workgroup`. Contains **0** `OSLogStore`/`OSLogEntry`/`getEntries` symbols.
- **`OSLog.swiftmodule`** (28 lines) — the Swift overlay for the OSLog clang module. Contains the `getEntries(with:at:matching:)` refinement (L11-14) and `OSLogMessageComponent.Argument`. `@_exported import OSLog`.

`import os` re-exports `os.log` (the OSLog clang module) plus the `OSLog.swiftmodule` overlay, so `OSLogStore`/`OSLogEntry`/`getEntries` are visible from `import os` alone. The `Foundation.swiftmodule` does **not** contain `Logger`/`OSLogStore`/`OSSignposter`. Do not look for them there.

The authoritative declarations for Nebula were read from:

- `iPhoneSimulator.sdk/usr/lib/swift/os.swiftmodule/arm64-apple-ios-simulator.swiftinterface`
- `XRSimulator.sdk/usr/lib/swift/os.swiftmodule/arm64-apple-xros-simulator.swiftinterface`
- `iPhoneSimulator.sdk/usr/lib/swift/OSLog.swiftmodule/arm64-apple-ios-simulator.swiftinterface` (getEntries)
- `XRSimulator.sdk/usr/lib/swift/OSLog.swiftmodule/arm64-apple-xros-simulator.swiftinterface` (getEntries)
- `OSLog.framework/Headers/Store.h` and `Entry.h` on iOS/macOS/watchOS/xrs SDKs (the ObjC headers carry `API_AVAILABLE`/`API_UNAVAILABLE` for `OSLogStore`/`OSLogStoreScope`/`OSLogEntry`)
- `Synchronization.swiftmodule/arm64-apple-ios-simulator.swiftinterface` (Mutex)

## Verified availability (all below the .v26 floor)

| Symbol | iOS | macOS | tvOS | watchOS | visionOS | Source |
|---|---|---|---|---|---|---|
| `OSLogType` (default/info/debug/error/fault) | 10.0 | 10.12 | 10.0 | 3.0 | 1.0* | os.swiftinterface L19-29 |
| `os.Logger` (Sendable @unchecked) | 14.0 | 11.0 | 14.0 | 7.0 | 1.0* | os.swiftinterface L1624 |
| `OSLogPrivacy` (.public/.private/.sensitive/.auto + mask:) | 14.0 | 11.0 | 14.0 | 7.0 | 1.0* | os.swiftinterface L1202-1203 |
| `OSLogPrivacy.Mask.hash` | 14.0 | 11.0 | 14.0 | 7.0 | 1.0* | os.swiftinterface L1220 (no per-case @available; inherits OSLogPrivacy) |
| `OSLogPrivacy.Mask._mail*` cases | 15.0 | 12.0 | 15.0 | 8.0 | 1.0* | os.swiftinterface L1220+ (per-case @available) |
| `OSLog.Category.pointsOfInterest` | 12.0 | 10.14 | 12.0 | 5.0 | 1.0* | os.swiftinterface L176-179 |
| `os.OSSignposter` (Sendable @unchecked) | 15.0 | 12.0 | 15.0 | 8.0 | 1.0* | os.swiftinterface L1901 |
| `SignpostMetadata` typealias (= OSLogMessage) | 15.0 | 12.0 | 15.0 | 8.0 | 1.0* | os.swiftinterface L1899 |
| `OSSignpostIntervalState` (class, @unchecked Sendable) | 15.0 | 12.0 | 15.0 | 8.0 | 1.0* | os.swiftinterface L2026 |
| `OSSignpostID` (struct, Sendable) | 12.0 | 10.14 | 12.0 | 5.0 | 1.0* | os.swiftinterface L161 |
| `OSLogStore` (ObjC class) | 15.0 | 10.15 | 15.0 | 8.0 | 1.0* | Store.h L48 |
| `OSLogStore.Scope.currentProcessIdentifier` | 15.0 | 12.0 | 15.0 | 8.0 | 1.0* | Store.h L30 (enum-level) |
| `OSLogStore.Scope.system` | **unavailable** | 12.0 | **unavailable** | **unavailable** | **uncertain** | Store.h L27 (API_UNAVAILABLE ios/tvos/watchos; visionOS NOT listed) |
| `OSLogStore.local()` | **unavailable** | 10.15 | **unavailable** | **unavailable** | **uncertain** | Store.h L72 (API_UNAVAILABLE ios/tvos/watchos; visionOS NOT listed) |
| `OSLogStore.getEntries(with:at:matching:)` (Swift overlay) | 15.0 | 10.15 | 15.0 | 8.0 | 1.0* | **OSLog.swiftmodule** L11-14 (NOT os.swiftmodule) |
| `OSLogEntry` + subclasses | 15.0 | 10.15 | 15.0 | 8.0 | 1.0* | Entry.h L77-79 |
| `Mutex<Value>` (Synchronization) | 18.0 | 15.0 | 18.0 | 11.0 | 2.0 | Synchronization.swiftmodule L7838 |
| `OSMetricOperation` (new signpost metrics) | 26.0 | 26.0 | 26.0 | 26.0 | 26.0 | xros os.swiftinterface L60 (**internal enum**) |

\* visionOS availability is expressed via the `*` fallback in the os/OSLog overlays (visionOS is never listed as `API_UNAVAILABLE` for these), so these APIs are available from visionOS 1.0+. The **only** explicit `visionOS 26.0` tag is `OSMetricOperation` — the new OS 26 signpost-metrics API — and it is `internal` to the os overlay, so it cannot be re-exported directly.

### Corrections to the original research

0. **`os.Logger` and `os.OSSignposter` CANNOT be wrapped (compile-proven, 2026-07-18).** The original "Public API surface" table proposed `NebulaLogger.error(_ message: OSLogMessage)` forwarding to `os.Logger.error(message)`, and `NebulaSignposter.emitEvent/beginInterval/endInterval/withIntervalSignpost` forwarding `name: StaticString`/`message: SignpostMetadata` to `os.OSSignposter`. **This does not compile** (verified with `swiftc -typecheck` on the Xcode 27 Beta 3 toolchain): `os.Logger`'s level methods (`@_semantics("oslog.requires_constant_arguments")`) AND `log(level:_:)` (`oslog.log_with_level`) reject a forwarded `OSLogMessage` ("argument must be a string interpolation"); `@_transparent`/`@inlinable`/`@_semantics` wrappers do NOT rescue it. `os.OSSignposter`'s signpost methods (`@_semantics("constant_evaluable")`) reject forwarded `name`/`message` ("globalStringTablePointer builtin must be used only on string literals"). The literal MUST appear at the `os.Logger`/`os.OSSignposter` call site. **Corrected design (shipped in Wave B, build-clean across all 5 platforms):** `NebulaLogger` exposes `public var osLogger` (redaction-preserving path) plus `String` convenience level methods that build `"\(message, privacy: .public)"` at the `os.Logger.log(level:_:)` call site (legal); `NebulaSignposter` exposes `public var osSignposter` for literal-requiring ops and keeps `makeSignpostID`/`isEnabled` + the ID/state wrappers. See `DECISIONS.md` ADR "os.Logger/os.OSSignposter CANNOT be wrapped".

1. **OSLogStore is NOT in os.swiftmodule.** `grep OSLogStore os.swiftmodule` returns 0. `getEntries` is in `OSLog.swiftmodule` L11-14. The original "os.swiftmodule L11-14 getEntries" and "OSLogEntry verified in os.swiftmodule" citations are wrong; the API and availability are otherwise correct.
2. **Mutex floor.** `Mutex<T>` is `@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)` (Synchronization L7838) — not merely "Swift 6.0+". `NebulaMemoryLogHandler`'s effective floor is iOS 18/macOS 15/visionOS 2.0 (still below .v26, no gating).
3. **Mask.hash.** `case hash`/`case none` have no per-case `@available` and inherit `OSLogPrivacy`'s macOS 11+/iOS 14+ floor. Only `_mail*` cases are macOS 12+/iOS 15+. `.private(mask: .hash)` works on macOS 11+/iOS 14+.
4. **Line drift.** `SignpostMetadata` is L1899 (not L2103); `OSSignpostIntervalState` is L2026 (not L2109). Types and availability are otherwise confirmed.
5. **visionOS .system/.local().** Store.h on xrs says `API_UNAVAILABLE(ios, tvos, watchos)` — it does **NOT** list visionOS. The original "visionOS unavailable" is unsupported by the header. Treat as macOS-only by safe gating; acknowledge this is conservative, not header-proven.

### Doc-vs-header conflict to flag

The JS-rendered [OSLogStore doc page](https://developer.apple.com/documentation/oslog/oslogstore) cannot be machine-verified (WebFetch returns only a JS shell, no body), but the original research reported it claims `Scope.system` is "iOS 15+/macOS 12+/tvOS 15+/watchOS 8+/visionOS 1.0+". This **contradicts** the authoritative `Store.h`:

```c
OSLogStoreSystem API_AVAILABLE(macos(12.0)) API_UNAVAILABLE(ios, tvos, watchos) = 0
```

**The C header wins** for iOS/tvOS/watchOS: `OSLogStore.Scope.system` and `OSLogStore.local()` are unavailable there. For visionOS the header is silent (not listed in `API_UNAVAILABLE`), so visionOS availability is **uncertain** — gate as macOS-only to be safe. Do not trust the rendered doc summary for availability; trust `API_AVAILABLE`/`API_UNAVAILABLE` in the headers.

### Gating idiom correction

`@available(macOS 12, *)` on a Swift declaration does **NOT** make it macOS-only — the `*` fallback makes it available on all other platforms from their first version. To make `NebulaLogStoreExporter.Scope.system` / `.local()` truly macOS-only, use one of:

```swift
// Option A: compile-time gate
#if os(macOS)
case system  // only on macOS
#endif

// Option B: explicit per-platform unavailability
@available(macOS 12, *)
@available(iOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)  // conservative; header is silent on visionOS
case system

// Option C: runtime guard that traps on non-macOS
case system:
  #if os(macOS)
  self.store = try OSLogStore(scope: .system)
  #else
  preconditionFailure("Scope.system is macOS-only")
  #endif
```

The underlying `OSLogStore.Scope.system` is already unavailable on iOS/tvOS/watchOS via the clang importer (so referencing it there is a compile error), but a Nebula wrapper enum `case system` does not inherit that unless explicitly annotated.

## Why not swift-log

[swift-log](https://github.com/apple/swift-log) provides `LoggerProtocol` + `LogHandler` backends with streaming and multiplexing. Nebula's binding constraints forbid third-party runtime deps, and `os.Logger` is strictly superior on Apple platforms: zero-cost compile-time string interpolation with per-argument privacy redaction, native Console.app / `log collect` integration, and Instruments signposts. The cost is that `OSLogMessage` requires **compile-time string literals** (`@_semantics("oslog.requires_constant_arguments")` on every level method, verified L1643/L1655/L1915), so messages cannot be built dynamically and passed around. This shapes the design below. See [WWDC20 "Explore logging in Swift"](https://developer.apple.com/videos/play/wwdc2020/10168/) for Apple's own guidance: `import os`, `Logger(subsystem:category:)`, `.debug/.info/.notice/.error/.fault`, `privacy: .public/.private/.private(mask: .hash)`.

## Recommended design for Nebula

Single SPM target `Nebula`, folder `Sources/Nebula/Logging/`. `import os` (re-exports the OSLog clang module + `OSLog.swiftmodule` overlay) + `import Foundation` + `import Synchronization` (for `Mutex<T>` in the in-memory sink). The contract mirrors the Cosmos sibling's `CosmosLogConfiguration` (Sendable struct + `@Sendable` handler + fluent `.with*` builders) but **without** SwiftUI `@Entry`/`@Observable` — Nebula is a foundation, not a UI library.

### Public API surface

| Symbol | Kind | Purpose |
|---|---|---|
| `NebulaLogLevel` | `public enum: Int, Sendable, Codable, CaseIterable` | Maps 1:1 to `os.OSLogType`: `debug`→`.debug`, `info`→`.info`, `notice`→`.default`, `error`→`.error`, `fault`→`.fault`. `warning` alias = `error` (matches `Logger.warning` internal mapping, os.swiftinterface L1655-1657: `osLogInternal(message, log: logObject, type: .error)`). |
| `NebulaLogCategory` | `public struct: Sendable, ExpressibleByStringLiteral` | String rawValue + presets `.networking/.persistence/.formatting/.measure/.concurrency/.general`. `os.Logger` takes a `String` category. |
| `NebulaLogger` | `public struct: Sendable` | Thin facade over `os.Logger` (`@unchecked Sendable`, L1624, macOS 11/iOS 14/watchOS 7/tvOS 14, visionOS 1.0+). Value type with `let` storage → derived Sendable without `@unchecked`. `init(subsystem:category:)`. `isEnabled(_:)`, `debug/info/notice/warning/error/fault/log(level:_:)` taking `OSLogMessage` (native privacy redaction preserved). `var signposter: NebulaSignposter` via `OSSignposter.init(logger:)` (L1914). |
| `NebulaLogEvent` | `public struct: Sendable` | Event for the handler fan-out path: `category`, `level`, `message: String`, `date`. Mirror of `CosmosLogEvent`. |
| `NebulaLogConfiguration` | `public struct: Sendable` | `isEnabled`, `subsystem`, `category`, `minLevel`, `handler: @Sendable (NebulaLogEvent)->Void`. `static let default` (once-token). Fluent `withSubsystem/withCategory/withMinLevel/withHandler/enabled`. `logger()` + `log(_:_:)`. |
| `NebulaSignposter` | `public struct: Sendable` | Wraps `os.OSSignposter` (`@unchecked Sendable`, L1901, macOS 12/iOS 15/watchOS 8/tvOS 15, visionOS 1.0+). `init(subsystem:category:)` defaulting to `OSLog.Category.pointsOfInterest` (L177-179). `emitEvent/beginInterval/endInterval/withIntervalSignpost<T>/makeSignpostID` (L1915-1998). |
| `NebulaSignpostID` | `public struct: Sendable` | Wraps `os.OSSignpostID` (struct Sendable, L161). `.exclusive/.invalid/.null` (L163-165). |
| `NebulaSignpostIntervalState` | `public struct: Sendable` | Wraps `os.OSSignpostIntervalState` (`@unchecked Sendable` class, L2026, macOS 12/iOS 15/watchOS 8/tvOS 15, visionOS 1.0+). Token from `beginInterval` → `endInterval`. |
| `NebulaSignpostMetadata` | `public typealias = os.SignpostMetadata` | = `os.OSLogMessage` (L1899, macOS 12/iOS 15/watchOS 8/tvOS 15, visionOS 1.0+). |
| `NebulaLogStoreExporter` | `public struct: Sendable` | Wraps `os.OSLogStore` (ObjC API_AVAILABLE macos 10.15/ios 15/tvos 15/watchos 8; `getEntries` in OSLog.swiftmodule L11-14, visionOS 1.0+). `init(scope:)` (`.currentProcessIdentifier` all platforms; `.system` macOS-only), `init(url:)`, `entries(options:position:matching:)`. `static local()` macOS-only. |
| `NebulaLogStoreExporter.Scope` | nested `public enum: Sendable` | `currentProcessIdentifier` (all 5 platforms) + `system` (macOS-only via `#if os(macOS)` or explicit per-platform unavailable — **not** `@available(macOS 12, *)` alone). |
| `NebulaMemoryLogHandler` | `public final class: @unchecked Sendable` | In-memory ring-buffer sink for tests/preview. `Mutex<[NebulaLogEvent]>`-backed (`Mutex` requires iOS 18/macOS 15/watchOS 11/tvOS 18/visionOS 2.0 — below .v26 floor, no gating). Exposes `handler` closure + `snapshot()`. |

### Two emission paths (important trade-off)

1. **Primary (native redaction):** `NebulaLogger.error("Failed \(url, privacy: .public) token=\(token, privacy: .private)")` — forwards an `OSLogMessage` straight to `os.Logger`. Per-argument privacy is preserved in Console.app. This is the path Apple intends ([WWDC20 10168](https://developer.apple.com/videos/play/wwdc2020/10168/)).
2. **Secondary (handler fan-out):** `config.log(.error, "Failed \(url)")` — takes a `String`, gates on `isEnabled && level >= minLevel`, emits to `os.Logger` as `\(message, privacy: .public)` **and** invokes `handler(NebulaLogEvent(...))`. The String path is `.public` by default and loses per-argument redaction. It exists so the in-memory sink / test handlers can capture events as plain `NebulaLogEvent` values. Document this loudly: **callers wanting redaction use path 1**.

### Concurrency

- `handler` is `@Sendable` (SE-0302) — may cross actor boundaries; capture only by-value `Sendable` state.
- `NebulaMemoryLogHandler`'s mutable ring buffer is guarded by `Mutex<T>` from `import Synchronization` (`@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)`, Synchronization L7838; [SE-0435](https://github.com/apple/swift-evolution/blob/main/proposals/0435-mutex.md)). **No `NSLock`, no `DispatchQueue`, no `nonisolated(unsafe)` mutable globals** — per the Nebula concurrency constraints (see [[nebula-swift6-concurrency]]). Effective floor of this type is iOS 18/macOS 15/visionOS 2.0 (still below .v26).
- One-time idempotent `NebulaLogConfiguration.default` via `static let` initializer side-effect (swift_once once-token pattern).
- `NebulaLogger`/`NebulaSignposter` are value types with `let` storage holding `@unchecked Sendable` os types, so derived `Sendable` conformance is sound without writing `@unchecked` on Nebula's own types (the `@unchecked` origin's safety is inherited — avoid mutable shared state inside them).

### Availability gating

The core surface needs **no `@available(iOS 26, *)`** — everything is at or below the `.v26` floor (`Logger` iOS 14, `OSSignposter` iOS 15, `OSLogStore` iOS 15, `Mutex` iOS 18 — all < 26). Exceptions:

- `NebulaLogStoreExporter.Scope.system` and `.local()` → macOS-only. Use `#if os(macOS)` or explicit per-platform `@available(<platform>, unavailable)` annotations (including `visionOS`, conservatively — the header is silent on visionOS). **Do not** use `@available(macOS 12, *)` alone; the `*` fallback would enable it on all platforms.
- `OSMetricOperation` (OS 26) is `internal` to the os overlay — it **cannot** be re-exported. If `NebulaSignposter` exposes metric APIs (add/subtract/set/reset), Nebula must define its own `public enum NebulaMetricOperation` and gate usage with `@available(iOS 26, *)` (== "since Nebula 26"). Defer to [[nebula-standardize-measure]] unless needed now.

## Apple patterns adopted

- `os.Logger` as the native unified-logging API — no swift-log, no third-party deps ([WWDC20 10168](https://developer.apple.com/videos/play/wwdc2020/10168/)).
- Subsystem + category split (subsystem = bundle id, category distinguishes subsystem parts).
- Compile-time `OSLogMessage` interpolation for zero-cost privacy redaction (`.public/.private/.sensitive/.auto`, `.private(mask: .hash)`) — preserved natively on `NebulaLogger` level methods.
- `os.OSLogType` five-level taxonomy; `NebulaLogLevel` maps 1:1; `warning` aliases `error` exactly as `Logger.warning` does internally (`type: .error`, L1655).
- `OSSignposter` + `OSLog.Category.pointsOfInterest` for Instruments-integrated measurement ([WWDC18 405](https://developer.apple.com/videos/play/wwdc2018/405/)).
- `OSLogStore.getEntries(with:at:matching:)` (OSLog.swiftmodule overlay) for field diagnostics ([WWDC23 10226](https://developer.apple.com/videos/play/wwdc2023/10226/)).
- `Sendable` value-type facade over `@unchecked Sendable` os types; `Mutex<T>` (Synchronization, iOS 18+/macOS 15+) for the in-memory sink; once-token idempotent default config.
- Cosmos contract pattern adapted (Sendable struct + `@Sendable` handler + fluent `.with*` builders) **without** SwiftUI `@Entry`/`@Observable`.
- DocC documentation for every public symbol; deprecation via `@available(*, deprecated, message:)` per Nebula versioning.

## Risks & open questions

- **File-citation error (fixed):** `OSLogStore`/`OSLogEntry`/`getEntries` are in the OSLog clang module + `OSLog.swiftmodule` overlay, NOT `os.swiftmodule`. Cite the right file.
- **Doc-vs-header conflict:** rendered [OSLogStore doc](https://developer.apple.com/documentation/oslog/oslogstore) reportedly says `.system` is iOS 15+; `Store.h` says macOS-only (unavailable iOS/tvOS/watchOS). Trust the header. Gate `Scope.system` and `.local()` as macOS-only.
- **visionOS uncertainty:** `Store.h` does NOT list visionOS in `API_UNAVAILABLE` for `.system`/`.local()`. The original "visionOS unavailable" assertion is unsupported. Gate macOS-only conservatively; confirm at compile time on the visionOS SDK if needed.
- **Gating idiom:** `@available(macOS 12, *)` alone does NOT make a symbol macOS-only (the `*` enables all platforms). Use `#if os(macOS)` or explicit per-platform `@available(<platform>, unavailable)`.
- **`OSLogMessage` requires compile-time literals** — cannot be built dynamically. The `config.log(level:_:)` String convenience path loses per-argument redaction (defaults `.public`). Document; steer redaction-sensitive callers to `NebulaLogger` directly.
- `os.Logger`/`os.OSSignposter` are `@unchecked Sendable` — Nebula wrappers inherit this origin; avoid mutable shared state inside them.
- `OSLogEntry` is an ObjC class hierarchy (not `Sendable`); crossing actors requires copying out primitive fields (`composedMessage`, `date`, `subsystem`, `category`) into a `Sendable` Nebula type.
- `OSMetricOperation` (OS 26) is `internal` to the os overlay — cannot be re-exported; Nebula must define its own public operation enum if it wants metric APIs. Decide now or defer to Nebula 27.
- `Mutex<T>` requires iOS 18/macOS 15/watchOS 11/tvOS 18/visionOS 2.0 (below .v26 floor, no gating) — `NebulaMemoryLogHandler`'s effective floor follows.
- `OSLogPrivacy.Mask._mail*` cases (iOS 15+) are underscore-prefixed/private-ish — do not expose through Nebula; stick to `.public/.private/.sensitive/.auto` and `.private(mask: .hash)`.
- **Open:** Should `NebulaLogLevel` add a `trace` alias (`Logger.trace` → `.debug`, L1643)? Should `NebulaLogCategory` be a String struct (flexible) or closed enum (consistent)? Does [[nebula-standardize-measure]] need the OS 26 metric APIs (remember `OSMetricOperation` is internal — Nebula needs its own enum)? Should `NebulaLogStoreExporter` bridge to `AsyncSequence`? Default subsystem `"com.nebula.foundation"` placeholder — require consumer-supplied bundle-id-derived subsystem instead? Does `NebulaMemoryLogHandler` belong in the main target (adds test-only public surface, floor iOS 18/macOS 15/visionOS 2.0) or a separate test-support module (would break the single-target rule)?

## Sources

- [Logger | Apple Developer Documentation](https://developer.apple.com/documentation/os/logger)
- [OSSignposter | Apple Developer Documentation](https://developer.apple.com/documentation/os/ossignposter)
- [OSLogStore | Apple Developer Documentation](https://developer.apple.com/documentation/oslog/oslogstore)
- [Explore logging in Swift — WWDC20 Session 10168](https://developer.apple.com/videos/play/wwdc2020/10168/)
- [Measuring Performance Using Logging — WWDC18 Session 405](https://developer.apple.com/videos/play/wwdc2018/405/)
- [Debug with structured logging — WWDC23 Session 10226](https://developer.apple.com/videos/play/wwdc2023/10226/)
- [SE-0435 Mutex / Synchronization module](https://github.com/apple/swift-evolution/blob/main/proposals/0435-mutex.md)
- Local ground-truth files (Xcode 27 Beta 3):
  - `iPhoneSimulator.sdk/usr/lib/swift/os.swiftmodule/arm64-apple-ios-simulator.swiftinterface` (Logger/OSSignposter/OSLogPrivacy/OSSignpostID/SignpostMetadata/OSSignpostIntervalState/OSLog.Category)
  - `XRSimulator.sdk/usr/lib/swift/os.swiftmodule/arm64-apple-xros-simulator.swiftinterface` (visionOS `*` fallback; OSMetricOperation L60)
  - `iPhoneSimulator.sdk/usr/lib/swift/OSLog.swiftmodule/arm64-apple-ios-simulator.swiftinterface` (`getEntries` L11-14)
  - `XRSimulator.sdk/usr/lib/swift/OSLog.swiftmodule/arm64-apple-xros-simulator.swiftinterface` (`getEntries` L11-14)
  - `iPhoneSimulator.sdk/usr/lib/swift/Synchronization.swiftmodule/arm64-apple-ios-simulator.swiftinterface` (Mutex L7838)
  - `OSLog.framework/Headers/Store.h`, `Entry.h` (iOS/macOS/watchOS/xrs SDKs)
- Sibling reference: `cosmos/Sources/Cosmos/Base/Configuration/CosmosLogConfiguration.swift`

Source of truth = root docs (CLAUDE.md, ARCHITECTURE.md, DECISIONS.md, VERSIONING.md); this note is the synthesis. On conflict, the root doc wins.
# Nebula

> A clean-room Swift foundation/architecture library for iOS, macOS, tvOS, watchOS, and visionOS 26.

## Overview

Nebula is a Swift foundation/architecture SwiftPM library — the sibling of [Cosmos](https://github.com/byescaleira/cosmos), the SwiftUI design system. It is distributed as a single SwiftPM module — one `import`, one target, no third-party dependencies. Nebula wraps Apple-native primitives (`os.Logger`, `FormatStyle`, `Measurement`, `Regex`, `AttributedString`, `Duration`/`Clock`, `Mutex`/`Atomic`) so every consumer reads the same Sendable contracts for logging, error reporting, formatting, and measurement — instead of carrying ad hoc configuration logic per project.

Four `Sendable` value-type contracts flow through explicit injection (there is no SwiftUI environment):

- **`NebulaLogConfiguration`** — logging behavior: level, category, subsystem, min level, `@Sendable` handler.
- **`NebulaErrorConfiguration`** — error reporting: isEnabled, category, `@Sendable` handler.
- **`NebulaStandards`** — formatting policy: locale, timeZone, calendar, `FormatStyle` accessors.
- **`NebulaMeasureConfiguration`** — measurement: clock, signposter, enabled, handler.

Plus a `Sendable` error envelope (`NebulaError`: `Error`/`LocalizedError`/`CustomNSError`/`Sendable`/`Hashable`) with lossy mapping from `NSError`/`DecodingError`/`URLError`/`CocoaError`/`any Error`, and extensions on Foundation value types (Date, String, Number, Primitives, Collections, Codable, Data/URL).

All default to sensible values, so every contract works **without any explicit injection**. Override a contract and the change propagates wherever you pass it.

## Requirements

- Swift 6.3+ toolchain, Swift language mode v6, Xcode 26.4+. (Xcode 26.0–26.3 shipped Swift 6.2 and will NOT parse a `swift-tools-version: 6.3` manifest — require Xcode 26.4+ for the Swift 6.3 path; OS-27-only SDK symbols compile-gated `#if swift(>=6.4)`.)
- Platforms, all at `.v26`: iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26.

Nebula is Foundation-native. It contains no `UIKit` symbols and no SwiftUI. It builds with zero concurrency warnings under Swift 6 mode — every public type is `Sendable` by derived conformance, every handler is `@Sendable`, and shared mutable state uses `Mutex`/`Atomic` from `import Synchronization` (never `NSLock`/`DispatchQueue`/`nonisolated(unsafe)`).

## Installation

Add Nebula to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/byescaleira/nebula.git", from: "0.1.0")
]
```

Then add `Nebula` to your target dependencies:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "Nebula", package: "nebula")
    ]
)
```

## Getting started

Import the module and use the contracts directly. No environment setup is required — defaults are already present:

```swift
import Nebula
import Foundation

// Logging — os.Logger façade with native privacy redaction
let logger = NebulaLogConfiguration.default
    .withSubsystem("com.example.app")
    .withMinLevel(.info)
    .logger()

// Redaction-sensitive: call the underlying os.Logger with an OSLogMessage
// literal so per-argument privacy is honored in Console.app. The simple
// String path below does NOT preserve per-argument redaction.
logger.osLogger.info("Started session \(sessionID, privacy: .private)")

// Simple dynamic-String path (defaults to .public — no per-argument redaction).
logger.info("Started session \(sessionID)")

// Errors — Sendable envelope with lossy mapping
let result = NebulaError.wrap {
    try JSONDecoder().decode(MyModel.self, from: data)
}
switch result {
case .success(let model):  print(model)
case .failure(let error):  NebulaErrorConfig.report(error)
}

// Formatting — modern FormatStyle façade
let standards = NebulaStandards.default
    .withLocale(Locale(identifier: "en_US_POSIX"))
    .withTimeZone(.gmt)

let iso = Date().formatted(standards.iso8601)
let bytes = Int64(1_536).formatted(standards.byteCount(style: .file))
let percent = 0.42.formatted(standards.percent())
```

## What is inside

Every public type is prefixed `Nebula`. Contracts are `Sendable` structs with `@Sendable` handlers and fluent `.with*` builders — no `@Entry`, no `@Observable`, no `@Environment`.

| Subsystem | Types |
|---|---|
| Logging | `NebulaLogger`, `NebulaLogConfiguration`, `NebulaLogLevel`, `NebulaLogCategory`, `NebulaLogEvent`, `NebulaSignposter`, `NebulaSignpostID`, `NebulaSignpostIntervalState`, `NebulaSignpostMetadata`, `NebulaMemoryLogHandler` |
| Errors | `NebulaError`, `NebulaError.Code`/`Kind`/`Context`/`Box`, `NebulaErrorConfiguration`, `NebulaErrorEvent`, `NebulaErrorConfig`, `NebulaDecodingError`, `NebulaEncodingError`, `NebulaNilError` |
| Extensions — DateTime | `Date`/`DateComponents`/`DateInterval`/`Calendar`/`Duration` extensions, `NebulaDateFormat`, `NebulaDurationFormat` |
| Extensions — String | `String`/`AttributedString` extensions, `NebulaRegex<Output>`, `NebulaRegexPatterns`, `NebulaStringDetectedEntity`, `NebulaStringAddressComponents`, `NebulaStringLocalization`, `NebulaHexEncodingOptions` |
| Extensions — Number | `BinaryInteger`/`BinaryFloatingPoint`/`Decimal`/`Measurement` extensions, `NebulaNumberFormatting`, `NebulaFormattingOptions`, `NebulaDecimalRoundingRule` |
| Extensions — Primitive | `Comparable.clamped(to:)`, `BinaryInteger.isEven`/`isOdd`/`times(_:)`, `Optional.or(_:)`/`orThrow(_:)`/`isNilOrEmpty`, `UUID.shortString`/`isValid(_:)` |
| Extensions — Collection | `nebulaChunked`/`nebulaWindows`/`nebulaUniqued`/`nebulaStablePartition`/`nebulaPartitioned`/`nebulaSorted`/`nebulaMerging` |
| Extensions — Codable | `NebulaJSONDecoder`/`NebulaJSONEncoder`, `NebulaJSONDecoderConfiguration`/`NebulaJSONEncoderConfiguration`, `Decodable.init(fromJSON:)`, `Encodable.toJSONData`/`toJSONString`, `Data.asPrettyJSONString` |
| Extensions — Data/URL | `Data.nebulaHexEncodedString`/`init?(nebulaHexEncoded:)`, `NebulaHashAlgorithm`, `Data.nebulaDigest`/`nebulaHexDigest`, `URL.nebulaAppending(queryItem:)`/`nebulaSettingQueryItem`/`nebulaRemovingQueryItem`/`nebulaPercentEncoded()`, `URLComponents.nebulaWith(queryItem:)` |
| Standardize | `NebulaStandards`, `NebulaStandardsConfig` (Date/ISO8601/Decimal/Integer/FloatingPoint/Measurement/Currency/Percent/ByteCount/List/PersonNameComponents/URL/Duration façade) |
| Measure | `NebulaMeasureConfiguration`, `NebulaMeasureResult`, `NebulaMeasureConfig` (`NebulaSignposter` lives under Logging) |

## Versioning

A Nebula major version equals the OS major it targets — the current baseline is **Nebula 26**. API availability is Nebula API versioning: "available since Nebula 26" corresponds to `@available(iOS 26, *)`. Above-floor minor bumps (e.g. "since Nebula 26.4") correspond to `@available(iOS 26.4, *)`. See [VERSIONING.md](VERSIONING.md) for the policy and the feature→OS gate reference table, and [CHANGELOG.md](CHANGELOG.md) for release history.

## Development

```bash
swift build
swift test
swift build -c release
```

Tests use Swift Testing (no UI snapshots, no ViewInspector — Nebula has no UI). Nebula has no third-party dependencies. Build for each target platform (iOS/macOS/tvOS/watchOS/visionOS) to confirm `#if os()` coverage; zero concurrency warnings under Swift 6 mode is mandatory.

## Documentation

Nebula ships an in-source DocC catalog at `Sources/Nebula/Nebula.docc/` (auto-discovered by SwiftPM because it sits inside the target's source directory). It builds natively in Xcode 26/27; for CLI generation, use `xcodebuild docbuild` (no `swift-docc-plugin` dependency — `Package.swift` keeps `dependencies: []` pristine):

```bash
xcodebuild docbuild -scheme Nebula -destination 'platform=macOS' -derivedDataPath /tmp/nebula-docc-dd
```

## Governance

- [ARCHITECTURE.md](ARCHITECTURE.md) — design goals and conventions
- [DECISIONS.md](DECISIONS.md) — architectural decisions
- [VERSIONING.md](VERSIONING.md) — versioning policy
- [ROADMAP.md](ROADMAP.md) — current and future work
- [CHANGELOG.md](CHANGELOG.md) — release history
- [CONTRIBUTING.md](CONTRIBUTING.md) — contribution guidelines
- [PROPOSAL.md](PROPOSAL.md) — foundation proposal

## License

MIT © Rafael Escaleira

---

Built by [Rafael Escaleira](https://byescaleira.com) · [@byescaleira](https://x.com/bybyescaleira)

If something here helped you, let me know. If something is wrong, tell me louder.
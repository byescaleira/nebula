---
tags: [foundation, codable]
aliases: [Nebula Codable, NebulaJSONDecoder, NebulaJSONEncoder]
related: [[nebula-errors], [nebula-spm-architecture], [nebula-swift6-concurrency], [nebula-logging]]
---

# Nebula Codable Foundation

The Codable layer of Nebula: configured, `Sendable` wrappers over `Foundation.JSONDecoder`/`JSONEncoder`, a Cosmos-style configuration contract with fluent builders, Codable convenience extensions, and a `DecodingError`/`EncodingError` -> `NebulaError` mapping. Ground truth is the installed `Foundation.swiftinterface` (Xcode 27 Beta 3 / Swift 6.4) for both **macOS** and **XROS (visionOS)** plus Apple docs — NOT memory. Verified 2026-07-18.

## Ground truth: what Foundation actually ships

From `Foundation.swiftmodule/arm64e-apple-macos.swiftinterface` (lines 8491-8642); the `arm64e-apple-xros.swiftinterface` uses identical `@available` lines:

- `JSONDecoder` and `JSONEncoder` are `open class`es, `@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)` (8491/8563). ([JSONDecoder](https://developer.apple.com/documentation/foundation/jsondecoder), [JSONEncoder](https://developer.apple.com/documentation/foundation/jsonencoder))
- Both conform to `Sendable` via an `@unchecked` extension, `@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)` (lines 8560-8561, 8641-8642). Because Nebula floors at OS 26 (`.v26`), this conformance is always present on all five target platforms.
- The strategy enums are all `Swift::Sendable`, and their `custom` cases take `@Sendable` closures (lines 8501, 8506, 8515, 8587, 8592, 8601):
  - `DateDecodingStrategy` / `DateEncodingStrategy`: `deferredToDate`, `secondsSince1970`, `millisecondsSince1970`, `iso8601` (`@available(macOS 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *)`), `formatted(DateFormatter)`, `custom(@Sendable)`.
  - `DataDecodingStrategy` / `DataEncodingStrategy`: `deferredToData`, `base64`, `custom(@Sendable)`. **No `base64Encode`** — that does not exist in the interface (the only `base64Encode*` tokens are unrelated `Data.base64EncodedString` / `Data.base64EncodedData` at lines 6754-6755).
  - `KeyDecodingStrategy`: `useDefaultKeys`, `convertFromSnakeCase`, `custom(@Sendable)`. **No `convertFromKebabCase`** — does not exist (grep returns 0 across all four interfaces).
  - `KeyEncodingStrategy`: `useDefaultKeys`, `convertToSnakeCase`, `custom(@Sendable)`.
  - `NonConformingFloat{Decoding,Encoding}Strategy`: `throw` / `convertFromString(...)` / `convertToString(...)`.
- `JSONEncoder.OutputFormatting` is an `OptionSet` that is `Sendable` (line 8565) with exactly three cases: `prettyPrinted`, `sortedKeys` (`@available(macOS 10.13, iOS 11.0, watchOS 4.0, tvOS 11.0, *)`), `withoutEscapingSlashes` (`@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)`). **No `fragmentsAllowed`** — grep returns 0 across all four Foundation interfaces.
- `allowsJSON5` and `assumesTopLevelDictionary`: `@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)` (lines 8542-8548).
- Codable-with-configuration: `EncodableWithConfiguration` / `DecodableWithConfiguration` / `CodableWithConfiguration` are `@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)` (lines ~13516-13537); the `decode(_:from:configuration:)` / `encode(_:configuration:)` overloads are `@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)` (lines 8554-8555 / 8635-8638). Apple also provides a second overload `decode<T,C>(_:from:configuration: C.Type)` / `encode<T,C>(_:configuration: C.Type)` at the same availability (8556-8557 / 8638).

Every one of those availability floors is **at or below OS 26**, and on visionOS each is available from visionOS 1.0+ (the `*` wildcard in the `@available` annotation grants visionOS 1.0+ when visionOS isn't named explicitly; the highest floor, iOS 17, maps to visionOS 1.0). So inside Nebula **no `@available` decorator is needed** for any of them — they are unconditionally available on iOS / macOS / tvOS / watchOS / visionOS at the `.v26` floor.

### Correction of two doc-fetch hallucinations (why we trust the interface)

WebFetch on Apple's JSONEncoder/JSONDecoder doc pages returned three APIs that **do not exist** in the interface:
1. `JSONEncoder.OutputFormatting.fragmentsAllowed` — does NOT exist. `fragmentsAllowed` is a `JSONSerialization.WritingOptions` member; `allowFragments` is the `JSONSerialization.ReadingOptions` member (different name). `JSONEncoder` always unions `WritingOptions.fragmentsAllowed` internally when calling `JSONSerialization`. Confirmed by grepping all four architecture interfaces (arm64e/x86_64 macos + macabi) — 0 hits — and by [swift-corelibs-foundation JSONEncoder.swift](https://github.com/apple/swift-corelibs-foundation/blob/main/Sources/Foundation/JSONEncoder.swift) + [swift PR #28818](https://github.com/apple/swift/pull/28818).
2. `KeyDecodingStrategy.convertFromKebabCase` and `DataEncodingStrategy.base64Encode` — neither appears in the interface.

The `.swiftinterface` is the source of truth and wins over a JS-rendered doc page that returned thin/hallucinated content.

### DecodingError (Swift stdlib)

Per [DecodingError docs](https://developer.apple.com/documentation/swift/decodingerror): four cases — `keyNotFound(CodingKey, Context)`, `valueNotFound(Any.Type, Context)`, `typeMismatch(Any.Type, Context)`, `dataCorrupted(Context)`. `Context` has `codingPath: [any CodingKey]`, `debugDescription: String`, `underlyingError: Error?`. iOS 8.0+ / macOS 10.10+ / tvOS 9.0+ / watchOS 2.0+ / visionOS 1.0+. ([SE-0167](https://github.com/apple/swift-evolution/blob/main/proposals/0167-swift-encoders.md), [SE-0166](https://github.com/apple/swift-evolution/blob/main/proposals/0166-swift-archival-serialization.md).) `EncodingError` has the single case `invalidValue(_:_:)` carrying the same `Context`.

> Note: `DecodingError`/`EncodingError`/`Codable`/`Encoder`/`Decoder`/containers live in the Swift stdlib `Swift` module. In this Xcode 27 Beta 3 toolchain they are not shipped as a textual `.swiftinterface` under `usr/lib/swift` the way Foundation is, so these specifics come from Apple docs (the strongest available ground truth for stdlib here).

### Top-level fragments

`JSONDecoder` **cannot** decode a top-level JSON fragment (bare number/string/bool/null) — it throws `DecodingError.dataCorrupted`. There is no `JSONDecoder` option to allow it; you must use `JSONSerialization.jsonObject(with:options:.allowFragments)` — the `ReadingOptions` case is **`.allowFragments`** (singular), NOT `.fragmentsAllowed`. `.fragmentsAllowed` is a `JSONSerialization.WritingOptions` member (used by `JSONSerialization.data(withJSONObject:options:)`). `JSONEncoder` already allows fragments internally (it unconditionally unions `.fragmentsAllowed`). See [[nebula-data-url-extensions]] for the broader serialization story.

## Recommended design for Nebula

Folder: `Sources/Nebula/Codable/` inside the single `Nebula` SPM target (see [[nebula-spm-architecture]]). No new module; `import Nebula` gives consumers everything. The contract style mirrors the Cosmos sibling package's `CosmosLogConfiguration` — a `Sendable` struct + `@Sendable` option closures + `static let default` + memberwise init with defaults — but WITHOUT SwiftUI `@Entry`/`@Observable` (Nebula is a foundation, not SwiftUI). Verified: `CosmosLogConfiguration.swift` exists and uses exactly that pattern.

### Configuration structs (derived-Sendable, no @unchecked)

```swift
public struct NebulaJSONDecoderConfiguration: Sendable {
    public var keyDecodingStrategy: JSONDecoder.KeyDecodingStrategy
    public var dateDecodingStrategy: JSONDecoder.DateDecodingStrategy
    public var dataDecodingStrategy: JSONDecoder.DataDecodingStrategy
    public var nonConformingFloatDecodingStrategy: JSONDecoder.NonConformingFloatDecodingStrategy
    public var allowsJSON5: Bool
    public var assumesTopLevelDictionary: Bool
    public var userInfo: [CodingUserInfoKey: any Sendable]

    public init(/* all defaulted to Apple's defaults */)
    public static let `default` = NebulaJSONDecoderConfiguration()

    // Fluent value-type-copy builders:
    public func withKeyDecodingStrategy(_ s: JSONDecoder.KeyDecodingStrategy) -> Self
    public func withDateDecodingStrategy(_ s: JSONDecoder.DateDecodingStrategy) -> Self
    public func withDataDecodingStrategy(_ s: JSONDecoder.DataDecodingStrategy) -> Self
    public func withNonConformingFloatDecodingStrategy(_ s: JSONDecoder.NonConformingFloatDecodingStrategy) -> Self
    public func withAllowsJSON5(_ b: Bool) -> Self
    public func withAssumesTopLevelDictionary(_ b: Bool) -> Self
    public func withUserInfo(_ info: [CodingUserInfoKey: any Sendable]) -> Self

    internal func makeDecoder() -> JSONDecoder   // configure once, freeze
}
```

`NebulaJSONEncoderConfiguration` mirrors: `outputFormatting: JSONEncoder.OutputFormatting`, `dateEncodingStrategy`, `dataEncodingStrategy`, `nonConformingFloatEncodingStrategy`, `keyEncodingStrategy`, `userInfo`, plus `.withOutputFormatting(_:)`, `.withPrettyPrinting()`, `.withSortedKeys()`, `.withDateEncodingStrategy(_:)`, etc., and `makeEncoder() -> JSONEncoder`.

Derived `Sendable` works because every field is `Sendable`: the strategy enums are `Sendable` (interface 8494/8503/8508/8512/8580/8589/8594/8598), `OutputFormatting` is a `Sendable OptionSet` (8565), `Bool`/`[CodingUserInfoKey: any Sendable]` are `Sendable`. No `@unchecked`.

### Wrapper structs (configure-once, freeze, hold in `let`)

```swift
public struct NebulaJSONDecoder: Sendable {
    public let configuration: NebulaJSONDecoderConfiguration
    private let decoder: JSONDecoder   // @unchecked Sendable; held immutably

    public init(_ configuration: NebulaJSONDecoderConfiguration = .default) {
        self.configuration = configuration
        self.decoder = configuration.makeDecoder()   // built once, never mutated
    }

    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T
    // No @available gate: decode(_:from:configuration:) is iOS 17+/macOS 14+ (interface 8554-8555),
    // below the Nebula .v26 floor on all five platforms (visionOS 1.0+ via the `*` wildcard).
    public func decode<T: DecodableWithConfiguration>(
        _ type: T.Type, from data: Data, configuration: T.DecodingConfiguration
    ) throws -> T
    public func decodeAsNebulaError<T: Decodable>(_ type: T.Type, from data: Data) -> Result<T, NebulaError>
}
```

`NebulaJSONEncoder` mirrors: `encode<T: Encodable>(_:) throws -> Data`, `encode<T: EncodableWithConfiguration>(_:configuration:) throws -> Data`, `encodeAsNebulaError(_:) -> Result<Data, NebulaError>`. Optionally also surface Apple's second overload `decode<T,C>(_:from:configuration: C.Type)` / `encode<T,C>(_:configuration: C.Type)` (interface 8556-8557 / 8638) for parity.

Why this is `Sendable` without `@unchecked`: `JSONDecoder`/`JSONEncoder` conform to `Sendable` (via the `@unchecked` extension, available iOS 16+/macOS 13+, always present at the .v26 floor). A struct holding a `Sendable` class in a `let` is derived-Sendable. Safety depends on the **configure-once-and-freeze** discipline: `makeDecoder()`/`makeEncoder()` are the only places that mutate the underlying instance, and the wrapper never re-exposes it. See [[nebula-swift6-concurrency]].

### DecodingError -> NebulaError mapping

```swift
public struct NebulaDecodingError: Sendable, Error {
    public enum Kind: Sendable { case keyNotFound, valueNotFound, typeMismatch, dataCorrupted }
    public let kind: Kind
    public let codingPath: [String]               // (key as? any CodingKey).stringValue
    public let expectedType: String?             // when present
    public let missingKey: String?               // when present
    public let debugDescription: String
    public let underlyingErrorDescription: String?
}
public struct NebulaEncodingError: Sendable, Error { /* codingPath, debugDescription, underlying */ }

extension NebulaError {
    public static func decoding(_ e: DecodingError) -> NebulaError
    public static func encoding(_ e: EncodingError) -> NebulaError
}
extension DecodingError { public var nebula: NebulaDecodingError }
extension EncodingError { public var nebula: NebulaEncodingError }
```

The mapping preserves Apple's `Context` fields faithfully rather than flattening to a string. `codingPath` is rendered to `[String]` because `any CodingKey` is an existential (not portably `Equatable`/trivially `Sendable` to expose verbatim). See [[nebula-errors]] for the foundation-wide `NebulaError`.

### Codable convenience extensions

```swift
extension Decodable {
    public init(fromJSON data: Data, using decoder: NebulaJSONDecoder = .init()) throws
    public static func decode(fromJSON data: Data, configuration: NebulaJSONDecoderConfiguration = .default) throws -> Self
}
extension Encodable {
    public func toJSONData(using encoder: NebulaJSONEncoder = .init()) throws -> Data
    public func toJSONString(using encoder: NebulaJSONEncoder = .init()) throws -> String?
}
extension Data { public var asPrettyJSONString: String? }   // [.prettyPrinted, .sortedKeys]
```

### What Nebula deliberately does NOT add

- No parallel strategy-enum hierarchy — Apple's are already `Sendable` with `@Sendable` closures; reuse them.
- No `.fragmentsAllowed` on the encoder (it does not exist on `OutputFormatting`). Document fragment decoding as a `JSONSerialization` concern using `.allowFragments` (ReadingOptions); fragment encoding uses `.fragmentsAllowed` (WritingOptions).
- No `convertFromKebabCase` / `base64Encode` (do not exist).
- No legacy `DateFormatter`-based defaults — prefer `.iso8601` or `.custom(@Sendable)` (DateFormatter is not `Sendable`). CAVEAT: Apple declares the strategy enums `Sendable` even though `.formatted(DateFormatter)` carries a non-Sendable `DateFormatter` — so a configuration using that case compiles as `Sendable` but is runtime-unsound; treat `.formatted(DateFormatter)` as an unsafe opt-in.

## Apple patterns adopted

- Cosmos-style contract (`Sendable` struct + `@Sendable` option closures + `static let default` + memberwise init with defaults), adapted from [CosmosLogConfiguration.swift](file:///Users/rafael.escaleira/Documents/projects/personal/cosmos/Sources/Cosmos/Base/Configuration/CosmosLogConfiguration.swift) — minus SwiftUI `@Entry`/`@Observable`.
- Reuse Apple's native strategy enums and `OutputFormatting` verbatim — Nebula adds ergonomics, not a re-implementation.
- Derived `Sendable` (no `@unchecked`, no `Mutex`) by holding the `@unchecked`-`Sendable` `JSONDecoder`/`JSONEncoder` in an immutable `let` after configure-once-and-freeze — matches Apple's per-instance/per-thread guidance while exposing a `Sendable` handle.
- Faithful `DecodingError.Context` preservation in `NebulaDecodingError`.
- Prefer modern strategies (`.iso8601`, `convertFromSnakeCase`/`convertToSnakeCase`, `.custom(@Sendable)`) over legacy Cocoa (`DateFormatter`, manual key munging, `ISO8601DateFormatter`).
- Expose `CodableWithConfiguration` overloads since that API (iOS 17+/macOS 14+) is below the .v26 floor.
- DocC on every public symbol; **no `@available` gating inside Nebula** (every consumed API <= OS 26 on all five platforms).

## Risks & open questions

- `@unchecked Sendable` of `JSONDecoder`/`JSONEncoder` is Apple's assertion, not compiler-verified. Nebula must enforce immutability-after-build; any future code path that mutates the held instance silently breaks `Sendable`. Mitigation: hold the instance `private`, never re-expose.
- `JSONDecoder` cannot decode top-level fragments — clients needing fragments must use `JSONSerialization.jsonObject(with:options:.allowFragments)` (ReadingOptions case is `.allowFragments`, NOT `.fragmentsAllowed`). For fragment encode, use `JSONSerialization.data(withJSONObject:options:[.fragmentsAllowed])`. Consider a small `NebulaJSONSerialization` opt-in helper naming both options correctly. See [[nebula-data-url-extensions]].
- `userInfo` is `[CodingUserInfoKey: any Sendable]` with `@preconcurrency` — passing non-`Sendable` values triggers Swift 6 warnings. Nebula must require `any Sendable`.
- `DateEncodingStrategy.formatted(DateFormatter)` / `DateDecodingStrategy.formatted(DateFormatter)` carry a non-`Sendable` `DateFormatter`; Apple's enums are nonetheless declared `Sendable`, so this case compiles-Sendable-but-unsound. Prefer `.iso8601` or `.custom(@Sendable)`; document `.formatted(DateFormatter)` as unsafe.
- `codingPath` as `[any CodingKey]` is an existential — `NebulaDecodingError` renders to `[String]`; loses typed `CodingKey`. Open whether to also keep raw existentials.
- `OutputFormatting.sortedKeys` sorts lexicographically by `String`, not by declaration order — document.
- `nonConformingFloatDecodingStrategy` defaults to `.throw`; `Infinity`/`NaN` from some APIs will be rejected. Document the tradeoff.
- Open: default `dateEncodingStrategy` — `.deferredToDate` (Apple default, Double) vs a `.iso8601` preset for typical JSON APIs. Recommendation: keep `.deferredToDate` default; ship a `NebulaJSONEncoderConfiguration.api` preset.
- Open: should `NebulaJSONDecoder` reuse one frozen `JSONDecoder` or build per-call? Recommendation: reuse the frozen one (`@unchecked Sendable`, never mutated -> safe to share).
- Open: surface both Apple CodableWithConfiguration overloads (`T.DecodingConfiguration` and the `C.Type` configuration-providing form) or just one?

## Sources

- [Foundation JSONDecoder — Apple Developer](https://developer.apple.com/documentation/foundation/jsondecoder)
- [Foundation JSONEncoder — Apple Developer](https://developer.apple.com/documentation/foundation/jsonencoder)
- [DecodingError — Swift Standard Library](https://developer.apple.com/documentation/swift/decodingerror)
- [EncodingError — Swift Standard Library](https://developer.apple.com/documentation/swift/encodingerror)
- [JSONSerialization.ReadingOptions — Apple Developer](https://developer.apple.com/documentation/foundation/jsonserialization/readingoptions) (`.allowFragments`)
- [JSONSerialization.WritingOptions — Apple Developer](https://developer.apple.com/documentation/foundation/jsonserialization/writingoptions) (`.fragmentsAllowed`)
- [SE-0167: Swift Encoders & Decoders](https://github.com/apple/swift-evolution/blob/main/proposals/0167-swift-encoders.md)
- [SE-0166: Swift Archival & Serialization](https://github.com/apple/swift-evolution/blob/main/proposals/0166-swift-archival-serialization.md)
- [swift-corelibs-foundation JSONEncoder.swift](https://github.com/apple/swift-corelibs-foundation/blob/main/Sources/Foundation/JSONEncoder.swift)
- [swift PR #28818 — Always allow JSON fragments](https://github.com/apple/swift/pull/28818)
- [swift-corelibs-foundation PR #2713 — JSONSerialization .withoutEscapingSlashes/.fragmentsAllowed](https://github.com/apple/swift-corelibs-foundation/pull/2713)
- Local ground truth (macOS): `/Applications/Xcode-27.0.0-Beta.3.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/Foundation.framework/Versions/C/Modules/Foundation.swiftmodule/arm64e-apple-macos.swiftinterface` lines 8491-8642, ~13516-13537
- Local ground truth (visionOS): `/Applications/Xcode-27.0.0-Beta.3.app/Contents/Developer/Platforms/XROS.platform/Developer/SDKs/XROS.sdk/System/Library/Frameworks/Foundation.framework/Modules/Foundation.swiftmodule/arm64e-apple-xros.swiftinterface` lines 8491-8642, ~13516-13537
- Sibling pattern: `file:///Users/rafael.escaleira/Documents/projects/personal/cosmos/Sources/Cosmos/Base/Configuration/CosmosLogConfiguration.swift`

Source of truth = root docs (CLAUDE.md, ARCHITECTURE.md, DECISIONS.md, VERSIONING.md); this note is the synthesis. On conflict, the root doc wins.
# Extensions

Nebula's extensions module groups gap-filling ergonomics on Foundation and stdlib value types into seven focused subdirectories, all derived `Sendable` and free of stdlib namespace pollution.

## Overview

Nebula extends Apple-native primitives rather than wrapping them behind opaque facades. The extensions are organized into seven groups:

- **DateTime** — ``NebulaDateFormat`` and ``NebulaDurationFormat`` presets, plus `Date`/`DateInterval` ergonomics. ISO and stable presets are pinned to `en_US_POSIX` + GMT for locale-independent output (logs, persistence, snapshots); the presentation-locale path lives in <doc:Standardize>.
- **String** — ``NebulaRegex``/``NebulaRegexPatterns``, ``NebulaStringDetectedEntity``, ``NebulaStringLocalization``, base64/hex encoding (``NebulaHexEncodingOptions``), case and detection ergonomics, and ``NebulaStringAddressComponents``.
- **Number** — ``NebulaNumberFormatting``, ``NebulaFormattingOptions``, ``NebulaDecimalRoundingRule``, plus `Decimal`/`BinaryInteger`/`BinaryFloatingPoint` ergonomics.
- **Primitive** — `Comparable.clamped(to:)`, `BinaryInteger.isEven`/`isOdd`/`times(_:)`, `Optional.or(_:)`/`orThrow(_:)`/`isNilOrEmpty`, `UUID.shortString`/`isValid(_:)`, and ``NebulaNilError``.
- **Collection** — open `Collection`/`Sequence` ergonomics (`nebulaChunked`, `nebulaWindows`, `nebulaUniqued`, `nebulaStablePartition`, `nebulaPartitioned`, `nebulaSorted`, `nebulaMerging`) with the `nebula*` prefix to avoid stdlib namespace pollution.
- **Codable** — ``NebulaJSONDecoder``/``NebulaJSONEncoder`` and their ``NebulaJSONDecoderConfiguration``/``NebulaJSONEncoderConfiguration``, `Decodable.init(fromJSON:)`, `Encodable.toJSONData()`/`toJSONString()`, `Data.asPrettyJSONString`, and the ``NebulaDecodingError``/``NebulaEncodingError`` bridges.
- **DataURL** — `Data`/`URL`/`URLComponents` ergonomics and ``NebulaHashAlgorithm`` (CryptoKit-backed).

### Naming conventions

Two rules govern the labels:

- **`nebula*` prefix on open `Collection`/`Sequence` ergonomics.** Methods like ``Collection/nebulaChunked(byCount:)`` and ``Collection/nebulaUniqued()`` are prefixed so they never collide with future stdlib additions — Nebula does not pollute the stdlib namespace.
- **Natural names on gap-fillers** where the stdlib deliberately lacks the API: `Comparable.clamped(to:)`, `Optional.or(_:)`, `BinaryInteger.isEven`. These are unambiguous and unlikely to be redeclared upstream.

### Never redeclare stdlib

Nebula reuses — never wraps — stdlib APIs that already exist: `Bool.toggle()` (SE-0199), `BinaryInteger.isMultiple(of:)` (Swift 5.0), `String.firstMatch(of:)`/`wholeMatch(of:)`/`matches(of:)` (iOS 16). Grep for collisions before shipping.

### No legacy Formatter subclasses

The public surface uses the Sendable `FormatStyle` family exclusively. `NumberFormatter`/`DateFormatter`/`MeasurementFormatter`/`ByteCountFormatter`/`ISO8601DateFormatter` are superseded. The single exception is `ListFormatter` (no `FormatStyle` replacement, not `Sendable`) — it is wrapped per-call, never cached.

### Above-floor gating

The 26.4 family — `Data.Base64EncodingOptions.base64URLAlphabet`/`.omitPaddingCharacter`, `String.Encoding.ianaName` and `init?(ianaName:)`, `UUID.random(using:)` — is gated with `@available(iOS 26.4, macOS 26.4, tvOS 26.4, watchOS 26.4, visionOS 26.4, *)`. Everything else in the module is below the `.v26` floor and ungated.

### Sendable, derived

Every extension on a value type derives `Sendable` when the base is `Sendable` — Nebula never authors `@unchecked Sendable` on a Nebula-defined value type.

```swift
// Collection ergonomics — prefixed to avoid stdlib collisions.
let chunks = [1, 2, 3, 4, 5].nebulaChunked(byCount: 2)        // [[1, 2], [3, 4], [5]]
let unique = [1, 1, 2, 3, 3].nebulaUniqued()                   // [1, 2, 3]

// Gap-fillers — natural names.
let clamped = 150.clamped(to: 0...100)                        // 100
let host: String? = nil
let resolved = host.or("localhost")                           // "localhost"

// Codable convenience — FormatStyle-era JSON coder/encoder.
let payload = try value.toJSONData(using: .init(dateStrategy: .iso8601))
let decoded = try MyType(fromJSON: payload)
```

## Topics

### DateTime
- ``NebulaDateFormat``
- ``NebulaDurationFormat``

### String
- ``NebulaRegex``
- ``NebulaRegexPatterns``
- ``NebulaStringDetectedEntity``
- ``NebulaStringLocalization``
- ``NebulaHexEncodingOptions``
- ``NebulaStringAddressComponents``

### Number
- ``NebulaNumberFormatting``
- ``NebulaFormattingOptions``
- ``NebulaDecimalRoundingRule``

### Primitive
- ``NebulaNilError``

### Codable
- ``NebulaJSONDecoder``
- ``NebulaJSONEncoder``
- ``NebulaJSONDecoderConfiguration``
- ``NebulaJSONEncoderConfiguration``
- ``NebulaDecodingError``
- ``NebulaEncodingError``

### DataURL
- ``NebulaHashAlgorithm``
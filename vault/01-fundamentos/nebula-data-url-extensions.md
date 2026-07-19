---
tags: [foundation, data-url-extensions, data, url, crypto]
aliases: [Nebula Data & URL Extensions, nebula-data, nebula-url]
related: [[nebula-codable-foundation], [nebula-string-extensions], [nebula-collection-extensions], [nebula-standardize-measure], [nebula-spm-architecture], [nebula-swift6-concurrency]]
---

# Nebula Data & URL Extensions

This note defines the `NebulaData` and `NebulaURL` extension surfaces for Nebula's foundation layer: hex/base64, slicing, String conversion, cryptographic checksums, and URL/query building, percent encoding, file-URL helpers. Ground truth is the installed `Foundation.swiftinterface` and `CryptoKit.swiftinterface` (Xcode 27 Beta.3 / Swift 6.4 SDK, arm64e-apple-macos), corroborated by Apple developer docs. See [[nebula-spm-architecture]] for the single-target layout and [[nebula-swift6-concurrency]] for the Sendable/Mutex constraints.

## Ground truth verified from the SDK

All availability below comes from grepping the `.swiftinterface` files, NOT from memory. Independent re-verification confirmed every claim below.

### Data (`Foundation.swiftinterface`, arm64e-apple-macos)

- `@frozen @_addressableForDependencies public struct Data : ... Swift::Sendable, Swift::Hashable` (line 5020) — Data is already `Sendable`; Nebula extensions inherit it. ([Foundation Data](https://developer.apple.com/documentation/foundation/data))
- Base64 (native): `public init?(base64Encoded base64String: String, options: Base64DecodingOptions = [])`, `public func base64EncodedString(options: Base64EncodingOptions = []) -> String`, `public func base64EncodedData(options: ...) -> Data` (lines 6752-6755) — `@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)`, under the .v26 floor (visionOS implicit 1.0+).
- **Base64 options above floor**: `extension Base64EncodingOptions { @available(macOS 26.4, iOS 26.4, tvOS 26.4, watchOS 26.4, visionOS 26.4, *) public static let base64URLAlphabet; @available(macOS 26.4, iOS 26.4, tvOS 26.4, watchOS 26.4, visionOS 26.4, *) public static let omitPaddingCharacter }` (lines 6745-6748). These are a *minor* OS 26 feature — above the .v26 major floor. Gate with `@available(iOS 26.4, *)` if exposed, or (recommended) defer to a Nebula 26.4 note.
- `public func subdata(in range: Range<Data.Index>) -> Data`, `public var count: Int`, `withUnsafeBytes`, and `Sequence`/`map` conformance — all baseline, no gating. Data also has `init<S>(_ elements: S) where S : Sequence, S.Element == UInt8` (line 5145) — used by `Data(SHA256.hash(data:))`.
- **No native hex**: a full grep of `Foundation.swiftinterface` for `hex` returns only `pathExtension`/`appendingPathExtension` (12982/12998) and `case hexadecimal` (23038, a `NumberFormatStyle` radix). There is NO `Data.hexEncodedString` or `init(hexEncoded:)`. Nebula must implement hex itself.

### URL / URLComponents / URLQueryItem

- `public struct URL : Swift::Equatable, Swift::Sendable, Swift::Hashable` (line 12842). `isFileURL` (12901), `pathComponents` (12976), `standardized` (13015), `standardizedFileURL` (13019) have **no `@available` annotation** ⇒ baseline on all 5 platforms. (Web tables claiming "iOS 16+" for `standardized` are wrong; the interface is authoritative.) ([Foundation URL](https://developer.apple.com/documentation/foundation/url))
- Modern URL APIs (all `@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)`, lines 13049-13060; visionOS implicit 1.0+): `init(filePath:directoryHint:relativeTo:)`, `appending(path:directoryHint:)`, `appending(queryItems:)`, `appending(component:)`, `appending(components:...)`, `DirectoryHint` enum, and the static directory helpers (`documentsDirectory`, `cachesDirectory`, etc.). NOTE: `appending(queryItems:)` accepts an **array only** — there is no single-item `appending(queryItem:)` (verified by grep), which justifies Nebula's single-item helper.
- Legacy APIs `appendingPathComponent` / `fileURLWithPath` / `appendPathComponent` are `@available(..., deprecated: 100000.0, message: "Use appending(path:directoryHint:) instead")` / `"Use init(filePath:directoryHint:relativeTo:) instead"` (lines 12849-12872, 12985-12990) — **must NOT be used** in Nebula.
- `URLComponents` (`@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)`, `Sendable`, line 13193): `init?(url:resolvingAgainstBaseURL:)` (13198, failable), `queryItems` (`@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)`, 13304), `percentEncodedQueryItems` (`@available(macOS 10.13, iOS 11.0, tvOS 11.0, watchOS 4.0, *)`, 13310), `encodedHost` (`@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)`, 13256). ([Foundation URLComponents](https://developer.apple.com/documentation/foundation/urlcomponents))
- `URLQueryItem` (`Sendable`, line 13349): `init(name:value:)`, `name: String`, `value: String?`.
- `URL.FormatStyle` / `.url` parseable format style (`@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)`, lines 16286/16298) — modern URL↔String.
- `ByteCountFormatStyle` (`@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)`, `Sendable`, line 20433) — modern byte-size formatting (replaces `ByteCountFormatter`). Relevant if a `Data.nebulaFormatted(.byteCount)` helper is wanted; otherwise lives in [[nebula-standardize-measure]].

### CryptoKit (`CryptoKit.swiftinterface`)

- `@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *) public struct SHA256 : Swift::Sendable` (line 307); SHA384 (319) and SHA512 (331) identical. visionOS is not listed ⇒ available from visionOS 1.0 — under the .v26 floor on all 5 platforms. ([CryptoKit SHA256](https://developer.apple.com/documentation/cryptokit/sha256))
- `@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, macCatalyst 13.0, *) @preconcurrency public protocol HashFunction : Swift::Sendable` (line 446) with `static func hash<D>(data: D) -> Self.Digest where D : Foundation::DataProtocol` (line 473), `mutating func update<D>(data: D)` (478), `func finalize() -> Self.Digest`. ([HashFunction](https://developer.apple.com/documentation/cryptokit/hashfunction))
- `@available(iOS 26.0, macOS 26.0, watchOS 26.0, tvOS 26.0, macCatalyst 26.0, visionOS 26.0, *) public typealias SHA2_256 = CryptoKit::SHA256` (line 305) — exactly at the Nebula 26 floor. SHA2_384 (317) / SHA2_512 (329) identical.
- `CryptoKit::Digest` is `@preconcurrency public protocol Digest : Foundation::ContiguousBytes, Swift::CustomStringConvertible, Swift::Hashable, Swift::Sendable, Swift::Sequence where Self.Element == Swift::UInt8` (line 200); `SHA256Digest` conforms via `extension CryptoKit::SHA256Digest : CryptoKit::Digest {}` (1767). Therefore `Data(SHA256.hash(data: self))` compiles.
- CryptoKit is an Apple framework (no third-party) — allowed by the binding constraints; it is the only non-Foundation import justified for this dimension.

### Synchronization (Mutex/Atomic)

- Ships only as binary prebuilt modules at `.../usr/lib/swift/<platform>/prebuilt-modules/27.0/Synchronization.swiftmodule` for all 5 platforms (iphoneos/appletvos/macosx/xros/watchos + simulators; no textual `.swiftinterface`). `Mutex<T>` / `Atomic<T>` are iOS 18+/macOS 15+/tvOS 18+/watchOS 11+/visionOS 2+ per Apple docs — under the floor. ([Synchronization Mutex](https://developer.apple.com/documentation/synchronization/mutex)) **Not needed** for these stateless extensions; do not import Synchronization here. See [[nebula-swift6-concurrency]] for where Mutex/Atomic apply.

## Recommended design for Nebula

### Module placement

Single SPM target `Nebula`, files under `Sources/Nebula/Extensions/`:

- `Data+Nebula.swift` — `extension Data` (NebulaData surface).
- `URL+Nebula.swift` — `extension URL` (NebulaURL surface).
- `URLComponents+Nebula.swift` — `extension URLComponents` (query-item helpers).
- `NebulaHashAlgorithm.swift` — `public enum NebulaHashAlgorithm: Sendable` wrapping CryptoKit `HashFunction`. This is the **only** file that `import CryptoKit`.

All public symbols are value types or pure functions → derived `Sendable`. No mutable shared state, so no `Mutex`/`Atomic`. The Cosmos Sendable-struct + `@Sendable`-handler + `.with*` builder pattern is reserved for [[nebula-logging]] / [[nebula-errors]] / [[nebula-standardize-measure]]; here we mirror only the `.with*` fluent-verb naming on the value type `URLComponents`.

### NebulaData (extension Data)

```swift
extension Data {
    // Hex — Foundation has no native hex.
    func nebulaHexEncodedString(uppercase: Bool = false) -> String
    init?(nebulaHexEncoded hex: String)        // nil on odd length / non-hex chars

    // Base64 — wraps native (iOS 8+/macOS 10.10+, under floor). Thin alias; see open question on whether to keep.
    func nebulaBase64String() -> String
    init?(nebulaBase64Encoded: String)

    // String ↔ Data (UTF-8) — symmetric helpers over Foundation.
    init?(nebulaUTF8String: String)
    var nebulaUTF8String: String?

    // Checksums via CryptoKit (in-scope; all 5 platforms ≤ .v26 floor).
    func nebulaDigest(of algorithm: NebulaHashAlgorithm) -> Data
    func nebulaHexDigest(of algorithm: NebulaHashAlgorithm = .sha256) -> String
}

public enum NebulaHashAlgorithm: Sendable {
    case sha256, sha384, sha512
    @available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    static let sha2_256: NebulaHashAlgorithm   // mirrors CryptoKit.SHA2_256 at floor
}
```

Implementation notes: `nebulaHexEncodedString` uses `lazy.map { String(format: "%02x", $0) }.joined()` (`%02X` when uppercase). `init?(nebulaHexEncoded:)` parses two-char pairs via `UInt8(_:radix:16)`, returns nil on invalid input — matches Foundation's failable-init convention (no throw). Digest: `Data(SHA256.hash(data: self))` — `SHA256.Digest` conforms to `CryptoKit::Digest` which is `Sequence<UInt8>` (CryptoKit.swiftinterface line 200), so `Data(_)` over the digest compiles; hex digest reuses `nebulaHexEncodedString`.

### NebulaURL (extension URL / URLComponents)

```swift
extension URL {
    // Query verbs Foundation does NOT provide (native has appending(queryItems:) for arrays only).
    func nebulaAppending(queryItem: URLQueryItem) -> URL?
    func nebulaAppendingQueryItems(_ items: [URLQueryItem]) -> URL?
    func nebulaSettingQueryItem(_ item: URLQueryItem) -> URL?   // replace same-name or append
    func nebulaRemovingQueryItem(named name: String) -> URL?
    func nebulaQueryItem(named name: String) -> URLQueryItem?
    func nebulaAppending(query: [String: String]) -> URL?        // dictionary → query items

    // Percent-encoding helpers (delegate to URLComponents.percentEncoded*; iOS 11+/macOS 10.13+).
    func nebulaPercentEncoded() -> String?
    func nebulaPercentDecoded() -> String?

    // File / resolving helpers.
    var nebulaDirectoryURL: URL?
    func nebulaResolving(against base: URL?) -> URL?
}

extension URLComponents {
    // Fluent value-type builders (return new struct) — Cosmos .with* style without SwiftUI.
    func nebulaWith(queryItem: URLQueryItem) -> URLComponents
    func nebulaWith(queryItems: [URLQueryItem]) -> URLComponents
    func nebulaSettingQueryItem(_ item: URLQueryItem) -> URLComponents
    func nebulaRemovingQueryItem(named name: String) -> URLComponents
    func nebulaWith(query: [String: String]) -> URLComponents
}
```

All helpers go through `URLComponents(url: self, resolvingAgainstBaseURL: true)` (failable, Foundation 13198) and return `components.url` (or nil). Pure value transformations — no locks, no `DispatchQueue`.

### Versioning

- All APIs target ≤ .v26 floor **except** `Base64EncodingOptions.base64URLAlphabet` / `.omitPaddingCharacter` (`@available(iOS 26.4, ...)`, Foundation 6745-6748) — a Nebula 26.4 feature. Recommendation: do **not** expose in v1; defer to a Nebula 26.4 minor note.
- `NebulaHashAlgorithm.sha2_256` is a Nebula 26 (floor) symbol (mirrors CryptoKit's `@available(iOS 26, *)` typealias at CryptoKit 305). Nebula targets the 5 platforms; the CryptoKit typealias also carries macCatalyst 26.0 — intentionally omitted unless macCatalyst becomes a target.
- If a Nebula wrapper later duplicates a native API (e.g. `appending(queryItems:)`), deprecate it with `@available(*, deprecated, message: "Use URL.appending(queryItems:) directly")`.

## Apple patterns adopted

- Prefer modern Swift APIs over legacy Cocoa: `URL.appending(path:directoryHint:)`, `appending(queryItems:)`, `init(filePath:directoryHint:relativeTo:)`, `URLComponents.percentEncodedQueryItems` / `encodedHost`. The legacy `appendingPathComponent` / `fileURLWithPath` are explicitly deprecated in the `.swiftinterface` (Foundation 12849-12872, 12985-12990) and must not be used.
- Use CryptoKit (`HashFunction` + `SHA256`/`384`/`512`, `hash(data:)` / `update(data:)` / `finalize()`) — the modern Swift crypto idiom — instead of CommonCrypto or third-party libs.
- Failable initializers return `nil` for malformed hex/base64/URL input rather than throwing — matches `init?(base64Encoded:)` and `URLComponents(url:resolvingAgainstBaseURL:)`.
- Value-type extensions only: `Data`/`URL`/`URLComponents` are already `Sendable`; Nebula additions are derived-Sendable with no `@unchecked` and no mutable shared state.
- Public-API prefix `Nebula` on every symbol (mirrors Cosmos `Cosmos`).
- Versioning via availability: gate iOS 26.4 base64 options with `@available(iOS 26.4, *)`; SHA-2 alias is a Nebula 26 symbol.
- DocC on every public symbol; deprecation via `@available(*, deprecated, message:)`.
- No UIKit / no SwiftUI symbols — Foundation + CryptoKit only.

## Risks & open questions

- **Base64 26.4 options** (`base64URLAlphabet`, `omitPaddingCharacter`) are above the .v26 *major* floor (minor 26.4, Foundation 6745-6748). Gate with `@available(iOS 26.4, *)` if exposed, or defer. Recommendation: defer.
- **CryptoKit link cost**: adding CryptoKit to the Nebula target is justified for hashing but must be the only non-Foundation import; keep all crypto behind `NebulaHashAlgorithm` so the rest of Nebula never imports it.
- **No native hex**: Nebula's hex implementation must validate even length and hex-only characters; define the contract (reject `0x` prefix? reject whitespace?) in DocC. The encode side via `String(format:)` is fine.
- **`URLComponents` nil path**: every `URL?`-returning helper must document when it returns nil (malformed URL / parse failure; failable init at Foundation 13198).
- **Dictionary query ordering**: `nebulaAppending(query: [String: String])` over an unordered Dictionary — decide whether to sort keys for determinism and document it.
- **WebFetch availability tables were wrong** for `percentEncodedQueryItems` (claimed iOS 16+, actually @available macOS 10.13/iOS 11.0/tvOS 11.0/watchOS 4.0 at Foundation 13310) and `standardized` (claimed iOS 16+, actually baseline at 13015). The `.swiftinterface` is the source of truth.
- **Mutex/Atomic not needed** here — importing `Synchronization` would be over-engineering for stateless extensions.
- **Base64 wrappers add little value**: `nebulaBase64String` / `init?(nebulaBase64Encoded:)` only alias native Foundation APIs that exist on every target platform. Consider omitting them to avoid the deprecation footgun; keep only if call-site clarity clearly justifies them.
- **Open**: include `CryptoKit.Insecure` (MD5/SHA1, iOS 13+; `Insecure.SHA1Digest`/`MD5Digest` exist at CryptoKit 1773-1775) for legacy checksums? Recommendation: SHA-2 only, with a documented security stance.
- **Open**: does URL *detection* (NSDataDetector / Regex) belong here or in a separate note? Recommendation: defer unless the user asks.
- **Open**: does byte-size formatting (`ByteCountFormatStyle`) belong here or in [[nebula-standardize-measure]]?
- **Open**: keep or omit the base64 wrappers given they only alias native APIs?

## Sources

- [Foundation Data — Apple Developer](https://developer.apple.com/documentation/foundation/data)
- [Foundation URL — Apple Developer](https://developer.apple.com/documentation/foundation/url)
- [Foundation URLComponents — Apple Developer](https://developer.apple.com/documentation/foundation/urlcomponents)
- [Foundation URLQueryItem — Apple Developer](https://developer.apple.com/documentation/foundation/urlqueryitem)
- [CryptoKit SHA256 — Apple Developer](https://developer.apple.com/documentation/cryptokit/sha256)
- [CryptoKit HashFunction — Apple Developer](https://developer.apple.com/documentation/cryptokit/hashfunction)
- [Foundation ByteCountFormatStyle — Apple Developer](https://developer.apple.com/documentation/foundation/bytecountformatstyle)
- [Synchronization Mutex — Apple Developer](https://developer.apple.com/documentation/synchronization/mutex)
- Foundation.swiftinterface (local): `file:///Applications/Xcode-27.0.0-Beta.3.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/Foundation.framework/Versions/C/Modules/Foundation.swiftmodule/arm64e-apple-macos.swiftinterface`
- CryptoKit.swiftinterface (local): `file:///Applications/Xcode-27.0.0-Beta.3.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/CryptoKit.framework/Versions/A/Modules/CryptoKit.swiftmodule/arm64e-apple-macos.swiftinterface`

Source of truth = root docs (CLAUDE.md, ARCHITECTURE.md, DECISIONS.md, VERSIONING.md); this note is the synthesis. On conflict, the root doc wins.
//
//  Data+Nebula.swift
//  Nebula
//
//  `Data` gap-fillers Foundation deliberately lacks: hex encode/decode, UTF-8
//  round-trip conveniences, SHA-2 digests via ``NebulaHashAlgorithm``, and
//  trap-free slicing. Thin base64 aliases are provided for call-site parity;
//  the above-floor (OS 26.4) URL-safe base64 helpers are gated with the full
//  five-platform `@available` family. See
//  vault/01-fundamentos/nebula-data-url-extensions.md.
//
//  Verified against the Xcode 27 Beta 3 SDK
//  (Foundation.swiftmodule/arm64e-apple-macos.swiftinterface):
//  - `Data` is `@frozen Sendable` (line 5020) — Nebula additions derive `Sendable`.
//  - `init?(base64Encoded:options:)` / `base64EncodedString(options:)` /
//    `base64EncodedData(options:)` are `@available(macOS 10.10, iOS 8.0, watchOS
//    2.0, tvOS 9.0, *)` (lines 6752–6755) — below the `.v26` floor.
//  - `Base64EncodingOptions.base64URLAlphabet` / `.omitPaddingCharacter` are
//    `@available(macOS 26.4, iOS 26.4, tvOS 26.4, watchOS 26.4, visionOS 26.4,
//    *)` (lines 6745–6748) — ABOVE the `.v26` major floor; gated below.
//  - `String.Encoding.ianaName` getter and `init?(ianaName:)` are also 26.4
//    (lines 12297, 12301) — not exposed here yet; see ``URL+Nebula`` notes.
//  - `init?(data:encoding:)` / `init?(bytes:encoding:)` are `@available(macOS
//    10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)` (below floor).
//  - `subdata(in:)` traps on out-of-bounds ranges; ``nebulaSubdata(in:)`` clamps.
//

import Foundation

extension Data {
    // MARK: - Hex

    /// Returns the lowercase (or `uppercase`) hexadecimal representation of
    /// `self`, two hex digits per byte.
    ///
    /// Foundation has no native hex encoding (a full grep of
    /// `Foundation.swiftinterface` for `hex` returns only `pathExtension` and a
    /// `NumberFormatStyle` radix case). This fills the gap.
    ///
    /// ```swift
    /// Data([0xDE, 0xAD, 0xBE, 0xEF]).nebulaHexEncodedString()        // "deadbeef"
    /// Data([0xDE, 0xAD, 0xBE, 0xEF]).nebulaHexEncodedString(uppercase: true)  // "DEADBEEF"
    /// ```
    ///
    /// - Parameter uppercase: `true` for `%02X` (uppercase), `false` (default)
    ///   for `%02x` (lowercase).
    public func nebulaHexEncodedString(uppercase: Bool = false) -> String {
        let format = uppercase ? "%02X" : "%02x"
        return self.lazy.map { String(format: format, $0) }.joined()
    }

    /// Creates data from a hexadecimal string, returning `nil` on malformed
    /// input.
    ///
    /// Accepts an **even-length** string of hex digits only. Whitespace, an
    /// optional `0x`/`0X` prefix, and any non-hex character cause `nil`. The
    /// contract matches Foundation's failable-init convention (no `throw`) and
    /// is case-insensitive (`"DEADBEEF"` and `"deadbeef"` produce the same
    /// bytes).
    ///
    /// ```swift
    /// Data(nebulaHexEncoded: "deadbeef")  // Data([0xDE, 0xAD, 0xBE, 0xEF])
    /// Data(nebulaHexEncoded: "xyz")      // nil
    /// Data(nebulaHexEncoded: "abc")      // nil (odd length)
    /// ```
    public init?(nebulaHexEncoded hex: String) {
        // Strip an optional `0x`/`0X` prefix.
        var body = hex
        if body.hasPrefix("0x") || body.hasPrefix("0X") {
            body.removeFirst(2)
        }
        guard body.count.isEven else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(body.count / 2)
        var index = body.startIndex
        while index < body.endIndex {
            let next = body.index(index, offsetBy: 2)
            guard let byte = UInt8(body[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }

    // MARK: - UTF-8 conveniences

    /// Creates `Data` from the UTF-8 encoding of `string`.
    ///
    /// Returns `nil` only if `string` cannot be encoded as UTF-8 — in practice
    /// every Swift `String` is UTF-8-representable, so this is effectively
    /// infallible; the failable signature is kept for symmetry with
    /// ``nebulaUTF8String`` and `String.init?(data:encoding:)`.
    public init?(nebulaUTF8String string: String) {
        guard let data = string.data(using: .utf8) else { return nil }
        self = data
    }

    /// The UTF-8 `String` decoded from `self`, or `nil` if the bytes are not
    /// valid UTF-8.
    ///
    /// Symmetric with ``init(nebulaUTF8String:)``; delegates to
    /// `String(data:encoding:)`.
    public var nebulaUTF8String: String? {
        String(data: self, encoding: .utf8)
    }

    // MARK: - Base64 (thin aliases over native, below floor)

    /// Returns the standard base64 encoding of `self`.
    ///
    /// Thin alias for `base64EncodedString()` (Foundation, iOS 8+/macOS
    /// 10.10+, below the `.v26` floor) preserved for call-site parity with the
    /// hex surface. Prefer the native API directly when the Nebula prefix is
    /// not desired.
    public func nebulaBase64String() -> String {
        base64EncodedString()
    }

    /// Creates data from a standard base64 `String`, returning `nil` on
    /// malformed input.
    ///
    /// Thin alias for `init?(base64Encoded:)`. Use `init?(nebulaBase64URLEncoded:)`
    /// for URL-safe (26.4) input.
    public init?(nebulaBase64Encoded string: String) {
        guard let data = Data(base64Encoded: string) else { return nil }
        self = data
    }

    // MARK: - Base64URL (above-floor, OS 26.4 — gated)

    /// Returns the URL-safe base64 encoding of `self` (RFC 4648 §5): `-`/`_`
    /// alphabet and no `=` padding.
    ///
    /// Fills the URL-safe-encoding gap with the OS 26.4
    /// `Base64EncodingOptions.base64URLAlphabet` / `.omitPaddingCharacter`
    /// (Foundation.swiftinterface lines 6745–6748). Gated with the full
    /// five-platform 26.4 family so the `.v26` watchOS/tvOS/visionOS builds do
    /// not see the symbol.
    @available(iOS 26.4, macOS 26.4, tvOS 26.4, watchOS 26.4, visionOS 26.4, *)
    public func nebulaBase64URLEncoded() -> String {
        base64EncodedString(options: [.base64URLAlphabet, .omitPaddingCharacter])
    }

    /// Creates data from a URL-safe (RFC 4648 §5) base64 `String`, returning
    /// `nil` on malformed input.
    ///
    /// Translates the URL-safe alphabet back to standard, restores `=` padding,
    /// and delegates to `init?(base64Encoded:)`. Accepts both padded and
    /// unpadded input. The decode path does not require a 26.4 decoder option
    /// (`Base64DecodingOptions` exposes no URL-alphabet member), so this
    /// initializer is **not** availability-gated — only the encode side is.
    public init?(nebulaBase64URLEncoded string: String) {
        // Translate URL-safe alphabet → standard.
        var standard = string
        standard = standard.replacingOccurrences(of: "-", with: "+")
        standard = standard.replacingOccurrences(of: "_", with: "/")
        // Restore padding to a multiple of 4.
        let remainder = standard.count % 4
        if remainder != 0 {
            standard.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: standard) else { return nil }
        self = data
    }

    // MARK: - SHA-2 digests (CryptoKit, below floor)

    /// Returns the SHA-2 digest of `self` as `Data`, using `algorithm`.
    ///
    /// Dispatches to ``NebulaHashAlgorithm/hash(_:)`` (the only Nebula surface
    /// that imports `CryptoKit`). All three algorithms are iOS 13+/macOS
    /// 10.15+/watchOS 6.0+/tvOS 13.0+/visionOS 1.0+ — below the `.v26` floor.
    ///
    /// ```swift
    /// let digest = Data("hello".utf8).nebulaDigest(of: .sha256)
    /// ```
    public func nebulaDigest(of algorithm: NebulaHashAlgorithm) -> Data {
        algorithm.hash(self)
    }

    /// Returns the lowercase hex SHA-2 digest of `self`, using `algorithm`
    /// (default `.sha256`).
    ///
    /// Convenience over ``nebulaDigest(of:)`` + `nebulaHexEncodedString(uppercase:)`.
    /// The output is lowercase by contract; pass the result through
    /// `uppercased()` for uppercase.
    public func nebulaHexDigest(of algorithm: NebulaHashAlgorithm = .sha256) -> String {
        nebulaDigest(of: algorithm).nebulaHexEncodedString()
    }

    // MARK: - Trap-free slicing

    /// Returns the subdata in `range`, clamped to `self`'s bounds.
    ///
    /// Fills the trap footgun in `subdata(in:)`: Foundation's API traps (signal
    /// 5) when `range` extends outside `count`. This helper intersects `range`
    /// with `0..<count` and returns an empty `Data` when the intersection is
    /// empty, so it is safe on untrusted offsets.
    ///
    /// ```swift
    /// let d = Data([0, 1, 2, 3, 4])
    /// d.nebulaSubdata(in: 2..<4)        // Data([2, 3])
    /// d.nebulaSubdata(in: 100..<200)    // Data() (clamped, not a trap)
    /// ```
    public func nebulaSubdata(in range: Range<Int>) -> Data {
        let safe = range.clamped(to: 0..<count)
        guard !safe.isEmpty else { return Data() }
        return subdata(in: safe)
    }
}
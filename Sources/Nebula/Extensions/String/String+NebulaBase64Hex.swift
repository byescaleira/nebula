//
//  String+NebulaBase64Hex.swift
//  Nebula
//
//  base64 + hex codecs on `String`. The base64 forwarders delegate to
//  `Data`'s Sendable `base64EncodedString(options:)` /
//  `init?(base64Encoded:options:)` (interface lines 6750–6756 — iOS 8/macOS
//  10.10, well below the .v26 floor). The hex surface delegates to the
//  shipped `Data` hex codec (`Data/nebulaHexEncodedString(uppercase:)`,
//  `Data/init?(nebulaHexEncoded:)`) for a single source of truth, adding
//  only the String-level `0x`-prefix / uppercase option layer. See
//  vault/01-fundamentos/nebula-string-extensions.md.
//
//  Above-floor option cases (`Data.Base64EncodingOptions.base64URLAlphabet`
//  at line 6746 and `.omitPaddingCharacter` at line 6748) are
//  `@available(iOS 26.4, macOS 26.4, tvOS 26.4, watchOS 26.4, visionOS 26.4, *)`
//  in the SDK. They are NOT redeclared here — callers passing them are
//  naturally gated by the SDK availability on the option itself; the
//  forwarders below take the option set without their own gate.
//

import Foundation

extension String {
    /// Encodes `self` (as UTF-8 bytes) to a base64 string.
    ///
    /// Forwards to `Data.base64EncodedString(options:)`. The above-floor
    /// option cases `.base64URLAlphabet` and `.omitPaddingCharacter`
    /// (available since Nebula 26.4) are passed through unchanged.
    ///
    /// - Parameter options: `Data.Base64EncodingOptions`, default `[]`.
    /// - Returns: The base64 representation of the receiver's UTF-8 bytes.
    public func base64EncodedString(options: Data.Base64EncodingOptions = []) -> String {
        Data(utf8).base64EncodedString(options: options)
    }

    /// Creates a `String` by base64-decoding `base64` and interpreting the
    /// resulting bytes as UTF-8.
    ///
    /// Forwards to `Data.init?(base64Encoded:options:)`. Returns `nil` if
    /// `base64` is not valid base64, or if the decoded bytes are not valid
    /// UTF-8.
    ///
    /// - Parameters:
    ///   - base64: A base64-encoded string.
    ///   - options: `Data.Base64DecodingOptions`, default `[]`.
    public init?(base64Encoded base64: String, options: Data.Base64DecodingOptions = []) {
        guard let data = Data(base64Encoded: base64, options: options),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        self = string
    }
}

/// Options for the Nebula hex *encoding* path (`String.hexEncodedString(options:)`).
///
/// Foundation ships no hex codec, so Nebula owns this small `OptionSet`. It
/// is `Sendable` by derived conformance (`Int`-backed `OptionSet`).
public struct NebulaHexEncodingOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Emit uppercase hex digits (`A`–`F`) instead of the default lowercase.
    public static let upperCase = NebulaHexEncodingOptions(rawValue: 1 << 0)
    /// Prepend the `0x` prefix to the encoded output.
    public static let prefix0x = NebulaHexEncodingOptions(rawValue: 1 << 1)
}

extension String {
    /// Encodes `self` (as UTF-8 bytes) to a hexadecimal string.
    ///
    /// A thin String-level convenience over the shipped `Data` hex codec
    /// (`Data.nebulaHexEncodedString(uppercase:)`): it encodes the
    /// receiver's UTF-8 bytes and optionally prepends a `0x` prefix. Round-
    /// trips with `init?(hexEncoded:)` for any UTF-8 string.
    ///
    /// - Parameter options: ``NebulaHexEncodingOptions``, default `[]`
    ///   (lowercase, no `0x` prefix).
    /// - Returns: The hex representation of the receiver's UTF-8 bytes.
    public func hexEncodedString(options: NebulaHexEncodingOptions = []) -> String {
        let hex = Data(utf8).nebulaHexEncodedString(uppercase: options.contains(.upperCase))
        return options.contains(.prefix0x) ? "0x" + hex : hex
    }

    /// Creates a `String` by hex-decoding `hex` and interpreting the resulting
    /// bytes as UTF-8.
    ///
    /// Delegates to `Data.init?(nebulaHexEncoded:)` (which tolerates an
    /// optional `0x`/`0X` prefix and either hex-digit case, and rejects
    /// odd-length bodies and non-hex characters), then re-interprets the
    /// bytes as UTF-8. Returns `nil` for malformed hex or non-UTF-8 bytes.
    ///
    /// - Parameter hex: A hex-encoded string, optionally `0x`-prefixed.
    public init?(hexEncoded hex: String) {
        guard let data = Data(nebulaHexEncoded: hex),
              let decoded = String(data: data, encoding: .utf8) else {
            return nil
        }
        self = decoded
    }
}
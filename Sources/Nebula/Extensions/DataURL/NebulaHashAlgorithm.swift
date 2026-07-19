//
//  NebulaHashAlgorithm.swift
//  Nebula
//
//  A `Sendable` enum selecting a SHA-2 hash algorithm for ``Data`` checksum
//  helpers. The **only** file in Nebula that `import CryptoKit` — the rest of
//  the data/url surface stays Foundation-only. Mirrors `CryptoKit.SHA2_256` /
//  `SHA2_384` / `SHA2_512` (iOS 13+, below the `.v26` floor). See
//  vault/01-fundamentos/nebula-data-url-extensions.md.
//
//  Verified against the Xcode 27 Beta 3 SDK
//  (CryptoKit.swiftmodule/arm64e-apple-macos.swiftinterface):
//  - `SHA256`/`SHA384`/`SHA512` are `@available(iOS 13.0, macOS 10.15, watchOS
//    6.0, tvOS 13.0, *)` `Sendable` structs (lines 307, 319, 331) — visionOS
//    implicit 1.0+; all under the `.v26` floor on every target.
//  - `HashFunction.hash(data:)` returns `Self.Digest` (line 473); `Digest` is a
//    `Sequence where Self.Element == UInt8` (line 200), so `Data(digest)` builds
//    via `Data`'s `init<S>(_ elements: S) where S : Sequence, S.Element == UInt8`.
//  - `SHA2_256`/`SHA2_384`/`SHA2_512` are `@available(iOS 26.0, …, visionOS 26.0,
//    macCatalyst 26.0, *)` typealiases (lines 305, 317, 329) — exactly at the
//    Nebula 26 floor. `sha2_256` below mirrors the alias without `macCatalyst`
//    (Nebula has no macCatalyst target).
//

import Foundation
import CryptoKit

/// A SHA-2 hash algorithm selectable for `Data` checksum helpers.
///
/// `NebulaHashAlgorithm` is a `Sendable` enum (derived — cases carry no state)
/// wrapping the three `CryptoKit` `HashFunction` types Nebula exposes. It is the
/// sole symbol that justifies `import CryptoKit` in this foundation; the
/// checksum entry points live on `Data` (`nebulaDigest(of:)` /
/// `nebulaHexDigest(of:)`) and dispatch to ``hash(_:)`` here, so the rest of
/// Nebula never imports `CryptoKit`.
///
/// `Insecure.SHA1`/`Insecure.MD5` are intentionally NOT exposed: SHA-2 is the
/// security floor for new code, and exposing legacy digests would invite
/// misuse. Consumers with a genuine legacy-checksum need should call `CryptoKit`
/// directly.
public enum NebulaHashAlgorithm: Sendable {
    /// SHA-256 (32-byte digest).
    case sha256
    /// SHA-384 (48-byte digest).
    case sha384
    /// SHA-512 (64-byte digest).
    case sha512

    /// The SHA-256 algorithm, mirroring `CryptoKit.SHA2_256` (Nebula 26 floor).
    ///
    /// Provided for source-level parity with `CryptoKit`'s `@available(iOS 26,
    /// *)` typealias (CryptoKit.swiftinterface line 305). Equivalent to
    /// ``sha256``.
    @available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    public static let sha2_256: NebulaHashAlgorithm = .sha256

    /// Computes the digest of `data` and returns it as `Data`.
    ///
    /// Dispatches to `CryptoKit` `SHA256`/`SHA384`/`SHA512` `hash(data:)`. The
    /// returned `Digest` is a `Sequence<UInt8>`, so `Data(_:)` builds it without
    /// copying through `ContiguousBytes`.
    public func hash(_ data: Data) -> Data {
        switch self {
        case .sha256: return Data(SHA256.hash(data: data))
        case .sha384: return Data(SHA384.hash(data: data))
        case .sha512: return Data(SHA512.hash(data: data))
        }
    }
}
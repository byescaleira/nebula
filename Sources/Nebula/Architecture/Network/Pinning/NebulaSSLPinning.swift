//
//  NebulaSSLPinning.swift
//  Nebula
//
//  Wave N17a — Network hardening. The SSL/TLS public-key pinning **policy**: a
//  `Sendable` value carrying per-host SPKI SHA-256 pin sets plus options. Pure
//  data — no `URLSession`, no `SecTrust` here. The evaluator
//  (``NebulaSSLPinningEvaluator``) consumes this; the delegate
//  (``NebulaURLSessionDelegate``) holds this.
//
//  Why a policy + evaluator + delegate split (and why pinning is NOT an
//  ``NebulaHTTPInterceptor``): a pinning failure surfaces as a `URLError`
//  from the `URLSession` *before/under* the `data(for:)` call, so the trust
//  evaluation has to happen at the `URLSessionDelegate` layer — an `adapt`/
//  `retry` interceptor cannot evaluate trust (it only mutates the
//  `URLRequest` / reacts to a thrown error). The interceptor surface
//  shipped in N10/0.7.0; N17a adds pinning as a separate transport concern.
//  The policy is pure data so it is unit-testable without a server; the
//  evaluator is a pure function over a `SecTrust` so it is unit-testable
//  with a synthetic trust (``NebulaSSLPinningEvaluator``); the delegate is a
//  thin wrapper whose only logic is an `internal` disposition helper
//  (``NebulaURLSessionDelegate/disposition(for:policy:trust:)``).
//
//  `import Security` is in-bounds — the Keychain precedent (`import Security`
//  in `Architecture/Keychain/`). `import CryptoKit` is NOT added here — the
//  SHA-256 of a public key goes through the existing `Data.nebulaDigest(of:)`
//  extension (the only `import CryptoKit` file is `NebulaHashAlgorithm.swift`);
//  this file is Foundation-only because it carries no digests, only the pins.
//
//  No `@available` gate — every pinning-relevant Apple symbol
//  (`URLSessionDelegate`, the `Sec*` family) is below the `.v26` floor on all
//  5 platforms. See vault/03-padroes/nebula-ssl-pinning.md.
//

import Foundation

/// A SHA-256 SPKI pin: the 32-byte digest of a certificate's public-key DER
/// external representation.
///
/// Construct from raw 32 bytes (``init(digest:)``) or a 64-char hex string
/// (``init(hexDigest:)``); round-trip via ``hexDigest``. The hex path delegates
/// to `Data.init(nebulaHexEncoded:)` (the single source of truth for the hex
/// codec) and re-validates the byte count so a non-32-byte hex string fails
/// rather than silently producing a malformed pin.
public struct NebulaSSLPinningPin: Sendable, Equatable, Hashable {

    /// The 32-byte SHA-256 digest.
    public let digest: Data

    /// Creates a pin from a 32-byte digest; returns `nil` for any other count.
    public init?(digest: Data) {
        guard digest.count == 32 else { return nil }
        self.digest = digest
    }

    /// Creates a pin from a 64-char hex digest string; returns `nil` for a
    /// non-hex string or a digest that is not exactly 32 bytes.
    public init?(hexDigest: String) {
        guard let data = Data(nebulaHexEncoded: hexDigest), data.count == 32 else { return nil }
        self.digest = data
    }

    /// The 64-char lowercase hex digest.
    public var hexDigest: String { digest.nebulaHexEncodedString() }
}

public extension NebulaSSLPinning {

    /// A per-host entry: the host plus its accepted SPKI pin set.
    struct HostPins: Sendable, Equatable, Hashable {

        /// The host name (matched exactly, then via ``NebulaSSLPinning/includeSubdomains``
        /// parent-domain walk).
        public let host: String

        /// The accepted pins for `host`. A certificate chain matches if **any**
        /// cert in the chain has a public key whose SHA-256 is in this set
        /// (OWASP "any position" pinning — survives leaf rotation).
        public let pins: Set<NebulaSSLPinningPin>

        /// Creates a per-host entry.
        public init(host: String, pins: Set<NebulaSSLPinningPin>) {
            self.host = host
            self.pins = pins
        }
    }
}

/// An SSL/TLS public-key pinning policy: per-host SPKI SHA-256 pin sets plus
/// options.
///
/// A `Sendable` value (all fields `Sendable` — `Data` / `String` / `Bool` /
/// `Set` / `[HostPins]`). Held by ``NebulaURLSessionDelegate``; consumed by
/// ``NebulaSSLPinningEvaluator``. Construct explicitly (no process-wide
/// accessor — pinning is per-session, unlike logging/measurement):
///
/// ```swift
/// let pin = NebulaSSLPinningPin(hexDigest: "d6d4c…")!
/// let policy = NebulaSSLPinning.pins(for: "api.example.com", [pin])
///     .withIncludeSubdomains(true)
/// let pinned = NebulaHTTPSession.pinned(by: policy)
/// let gateway = NebulaHTTPGateway(.init(endpoint: URL(string: "https://api.example.com")!),
///                                  session: pinned.session)
/// ```
///
/// Pinning is **additive to system trust**: ``validateChainFirst`` defaults to
/// `true`, so the OS trust store is evaluated first and pinning only adds a
/// constraint on top — it never replaces the OS anchors. Carry a backup pin
/// (OWASP guidance) so a certificate rotation does not lock out the app.
public struct NebulaSSLPinning: Sendable, Equatable, Hashable {

    /// The per-host pin entries.
    public let hostPins: [HostPins]

    /// When `true`, a host with no exact entry is matched by walking parent
    /// domains (`api.example.com` → `example.com`) and using the first parent
    /// with pins. Default `false` (exact host match only).
    public let includeSubdomains: Bool

    /// When `true` (default), the OS trust store is evaluated first via
    /// `SecTrustEvaluateWithError`; a chain that the OS rejects fails before
    /// pin matching. Set `false` to rely solely on pin matching (e.g.
    /// offline-only / pinned-CA rotation windows).
    public let validateChainFirst: Bool

    /// When `true` (default), a host with no applicable pin fails **closed**
    /// (the challenge is cancelled). When `false`, an unknown host falls
    /// through to `URLSession`'s default handling (no pin enforcement).
    public let failClosedForUnknownHosts: Bool

    /// Creates a pinning policy.
    public init(
        hostPins: [HostPins],
        includeSubdomains: Bool = false,
        validateChainFirst: Bool = true,
        failClosedForUnknownHosts: Bool = true
    ) {
        self.hostPins = hostPins
        self.includeSubdomains = includeSubdomains
        self.validateChainFirst = validateChainFirst
        self.failClosedForUnknownHosts = failClosedForUnknownHosts
    }

    /// A single-host convenience policy (chain-first, fail-closed, no
    /// subdomains).
    public static func pins(for host: String, _ pins: Set<NebulaSSLPinningPin>) -> NebulaSSLPinning {
        .init(hostPins: [.init(host: host, pins: pins)])
    }

    // MARK: - Fluent builders (mirror ``NebulaGatewayConfiguration``)

    /// Returns a copy with the host-pins replaced.
    public func withHostPins(_ hostPins: [HostPins]) -> NebulaSSLPinning {
        .init(hostPins: hostPins, includeSubdomains: includeSubdomains,
              validateChainFirst: validateChainFirst,
              failClosedForUnknownHosts: failClosedForUnknownHosts)
    }

    /// Returns a copy with `includeSubdomains` replaced.
    public func withIncludeSubdomains(_ includeSubdomains: Bool) -> NebulaSSLPinning {
        .init(hostPins: hostPins, includeSubdomains: includeSubdomains,
              validateChainFirst: validateChainFirst,
              failClosedForUnknownHosts: failClosedForUnknownHosts)
    }

    /// Returns a copy with `validateChainFirst` replaced.
    public func withValidateChainFirst(_ validateChainFirst: Bool) -> NebulaSSLPinning {
        .init(hostPins: hostPins, includeSubdomains: includeSubdomains,
              validateChainFirst: validateChainFirst,
              failClosedForUnknownHosts: failClosedForUnknownHosts)
    }

    /// Returns a copy with `failClosedForUnknownHosts` replaced.
    public func withFailClosedForUnknownHosts(_ failClosedForUnknownHosts: Bool) -> NebulaSSLPinning {
        .init(hostPins: hostPins, includeSubdomains: includeSubdomains,
              validateChainFirst: validateChainFirst,
              failClosedForUnknownHosts: failClosedForUnknownHosts)
    }
}
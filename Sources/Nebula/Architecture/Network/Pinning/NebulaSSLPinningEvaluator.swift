//
//  NebulaSSLPinningEvaluator.swift
//  Nebula
//
//  Wave N17a — Network hardening. The pure SSL/TLS trust evaluator: a `static`
//  function over a `SecTrust` + host + ``NebulaSSLPinning`` policy. No
//  `URLSession` dependency — call from ``NebulaURLSessionDelegate`` or from
//  tests with a synthetic `SecTrust`.
//
//  The split is the testability lever: the evaluator is a pure function, so it
//  is unit-testable on the macOS host with a synthetic `SecTrust` built via
//  `SecCertificateCreateWithData` + `SecTrustCreateWithCertificates` from a
//  self-signed test cert embedded as a `[UInt8]` literal — no live TLS server,
//  no `URLSession`, no `URLProtectionSpace` (whose `serverTrust` is not
//  injectable via the public init, which is why the delegate method itself is
//  not round-trip unit-tested). The host-lookup (exact + subdomain walk) is
//  factored as an `internal` helper so it is independently testable.
//
//  Verified Security API ground truth (Xcode 27 Beta 3 SDK headers — the
//  Security framework is a C/Obj-C framework via `module.modulemap`, there is
//  no `.swiftinterface`; WebFetch hallucinates availability, the headers are
//  authoritative). All symbols below are below the `.v26` floor on every
//  platform → no `@available` gate:
//  - `SecTrustEvaluateWithError(_:_:)`            — `SecTrust.h:425` (mac 10.14 / iOS 12 / tvOS 12 / watchOS 5)
//  - `SecTrustCopyCertificateChain(_:)`           — `SecTrust.h:655` (mac 12 / iOS 15 / tvOS 15 / watchOS 8) — preferred over deprecated `SecTrustGetCertificateAtIndex`
//  - `SecCertificateCopyKey(_:)`                  — `SecCertificate.h:155` (mac 10.14 / iOS 12 / tvOS 12 / watchOS 5) — cross-platform; NOT the platform-split deprecated `SecCertificateCopyPublicKey`
//  - `SecKeyCopyExternalRepresentation(_:_:)`    — `SecKey.h:854` (mac 10.12 / iOS 10 / tvOS 10 / watchOS 3)
//
//  The SHA-256 of the public-key DER goes through `Data.nebulaDigest(of:)`
//  (→ ``NebulaHashAlgorithm``/sha256 → `CryptoKit.SHA256`) — no new
//  `import CryptoKit` here (the only file that imports CryptoKit is
//  `NebulaHashAlgorithm.swift`). See vault/03-padroes/nebula-ssl-pinning.md.
//

import Foundation
import Security

/// The result of evaluating a `SecTrust` against a ``NebulaSSLPinning`` policy.
public enum NebulaSSLPinningResult: Sendable, Equatable {

    /// A certificate in the chain has a public key whose SHA-256 SPKI digest is
    /// pinned for the host. `certificateIndex` is the position in the trust
    /// chain (leaf = 0).
    case matched(pin: NebulaSSLPinningPin, certificateIndex: Int)

    /// The chain validated and pins applied, but no cert's SPKI digest matched.
    case noMatchingPin

    /// No pin set applies to the host (the delegate maps this to fail-closed
    /// or default handling via ``NebulaSSLPinning/failClosedForUnknownHosts``).
    case noPinForHost

    /// The OS trust store rejected the chain (``NebulaSSLPinning/validateChainFirst``
    /// is `true`). `message` is a lossy description of the underlying `CFError`.
    case chainValidationFailed(message: String)

    /// The certificate chain could not be copied, or no certificate in the
    /// chain yielded a public key (or its DER external representation) — i.e.
    /// SPKI extraction failed for the whole chain, so no digest could be
    /// compared against the pin set. (A single un-extractable key is not fatal
    /// — the evaluator skips it and tries the next cert.)
    case spkiExtractionFailed(message: String)
}

/// A pure, testable evaluator that runs the SPKI-hash pinning algorithm against
/// a `SecTrust`. No `URLSession` dependency.
public enum NebulaSSLPinningEvaluator {

    /// Evaluates `trust` for `host` against `policy`.
    ///
    /// Algorithm (OWASP "any position" SPKI pinning, additive to system trust):
    /// 1. If `policy.validateChainFirst`, run `SecTrustEvaluateWithError`; a
    ///    chain the OS rejects fails here (`.chainValidationFailed`).
    /// 2. Resolve the pin set for `host` (exact match, then a parent-domain
    ///    walk when `policy.includeSubdomains`); no applicable pin → `.noPinForHost`.
    /// 3. Copy the certificate chain via `SecTrustCopyCertificateChain`.
    /// 4. For each cert, extract its public key (`SecCertificateCopyKey`),
    ///    its DER external representation (`SecKeyCopyExternalRepresentation`),
    ///    and SHA-256 it (`Data.nebulaDigest(of: .sha256)`); a digest in the
    ///    pin set → `.matched`. Matching **any** cert in the chain (leaf or
    ///    intermediate/CA) survives leaf rotation.
    /// 5. No cert matched → `.noMatchingPin`.
    public static func evaluate(
        trust: SecTrust,
        host: String,
        policy: NebulaSSLPinning
    ) -> NebulaSSLPinningResult {
        if policy.validateChainFirst {
            var cfError: CFError?
            if !SecTrustEvaluateWithError(trust, &cfError) {
                let message = cfError.map { ($0 as Error).localizedDescription }
                    ?? "chain validation failed"
                return .chainValidationFailed(message: message)
            }
        }

        guard let pins = resolvedPins(for: host, policy: policy) else {
            return .noPinForHost
        }

        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else {
            return .spkiExtractionFailed(message: "could not copy certificate chain")
        }

        // Track whether any cert yielded a digestable SPKI: if every cert in
        // the chain failed key/DER extraction, the failure is "could not
        // extract an SPKI" (``NebulaSSLPinningResult/spkiExtractionFailed``),
        // not "no pin matched" — a truthful diagnostic for a caller bridging to
        // ``NebulaSSLPinningError``. A single un-extractable key is not fatal.
        var extractedAny = false
        for (index, certificate) in chain.enumerated() {
            guard let key = SecCertificateCopyKey(certificate) else {
                continue  // try the next cert; a single un-extractable key is not fatal
            }
            var keyError: Unmanaged<CFError>?
            guard let der = SecKeyCopyExternalRepresentation(key, &keyError) else {
                continue
            }
            extractedAny = true
            let digest = (der as Data).nebulaDigest(of: .sha256)
            if let pin = NebulaSSLPinningPin(digest: digest), pins.contains(pin) {
                return .matched(pin: pin, certificateIndex: index)
            }
        }

        if !extractedAny {
            return .spkiExtractionFailed(
                message: "could not extract a public key from any certificate in the chain"
            )
        }
        return .noMatchingPin
    }

    /// Resolves the applicable pin set for `host`: exact match first, then a
    /// parent-domain walk when `policy.includeSubdomains`. Returns `nil` when
    /// no pin set applies. `internal` so the test module covers the lookup
    /// (including the subdomain walk) independently of a `SecTrust`.
    ///
    /// Host matching is **case-insensitive** (RFC 1035 — DNS names are ASCII
    /// case-insensitive; `URLProtectionSpace.host` is delivered lowercase). The
    /// input `host` and the stored ``NebulaSSLPinning/HostPins/host`` values are
    /// both `.lowercased()` before comparison so a caller who configures a
    /// mixed-case host still matches; stored data is not mutated.
    internal static func resolvedPins(
        for host: String,
        policy: NebulaSSLPinning
    ) -> Set<NebulaSSLPinningPin>? {
        let normalized = host.lowercased()
        // Exact host match.
        if let exact = policy.hostPins.first(where: { $0.host.lowercased() == normalized }) {
            return exact.pins
        }
        guard policy.includeSubdomains else { return nil }

        // Parent-domain walk: for "a.b.example.com" try "b.example.com",
        // "example.com" — stopping before the single-label public suffix.
        let labels = normalized.split(separator: ".").map(String.init)
        guard labels.count >= 3 else { return nil }
        for i in 1..<(labels.count - 1) {
            let parent = labels[i...].joined(separator: ".")
            if let entry = policy.hostPins.first(where: { $0.host.lowercased() == parent }) {
                return entry.pins
            }
        }
        return nil
    }
}
//
//  ArchitectureSSLPinningTests.swift
//  NebulaTests
//
//  Wave N17a — Network hardening. Unit tests for the SSL/TLS public-key
//  pinning surface:
//  - A. value semantics (``NebulaSSLPinningPin`` / ``NebulaSSLPinning``),
//  - B. host lookup + subdomain walk (the `internal`
//    ``NebulaSSLPinningEvaluator/resolvedPins(for:policy:)`` helper),
//  - C. SPKI extraction against a **synthetic `SecTrust`** built from a
//    self-signed RSA test certificate embedded as a `[UInt8]` literal (no SPM
//    `resources:`) — the high-value test that exercises the real Security
//    API path on the macOS host without a live TLS server,
//  - D. the delegate's disposition mapping (the `internal`
//    ``NebulaURLSessionDelegate/disposition(for:policy:trust:)`` seam).
//
//  Documented limitation: the live `URLSession` + delegate round-trip over real
//  TLS is NOT exercised — `URLProtectionSpace.serverTrust` is `nil` unless the
//  system created the space during a real handshake, and the public
//  `URLProtectionSpace.init(host:port:protocol:realm:authenticationMethod:)`
//  has no `serverTrust` parameter, so no in-process synthetic challenge can
//  exercise the pinning branch. The evaluator + `disposition(for:policy:trust:)`
//  cover the logic completely (mirrors the ``NebulaUNNotificationCenter``
//  precedent). See vault/03-padroes/nebula-ssl-pinning.md.
//

import Testing
import Foundation
import Security
import Synchronization
@testable import Nebula

@Suite struct ArchitectureSSLPinningTests {

    // MARK: - A. Value semantics

    @Test func pinAccepts32ByteDigestRejectsOtherCounts() {
        let bytes = Data(repeating: 0xAB, count: 32)
        #expect(NebulaSSLPinningPin(digest: bytes) != nil)
        #expect(NebulaSSLPinningPin(digest: Data(repeating: 0xAB, count: 31)) == nil)
        #expect(NebulaSSLPinningPin(digest: Data(repeating: 0xAB, count: 33)) == nil)
        #expect(NebulaSSLPinningPin(digest: Data()) == nil)
    }

    @Test func pinAcceptsHexDigestRoundTrips() {
        let hex = "7badc2c8e548c45f08e381188ad1aa7fae4addc57eb8aee78f17478482ad3b2a"
        let upper = hex.uppercased()
        let pin = NebulaSSLPinningPin(hexDigest: hex)
        let pinUpper = NebulaSSLPinningPin(hexDigest: upper)
        #expect(pin != nil)
        #expect(pinUpper != nil)
        #expect(pin == pinUpper)
        #expect(pin?.hexDigest == hex)  // round-trip (lowercase)
    }

    @Test func pinRejectsMalformedHex() {
        #expect(NebulaSSLPinningPin(hexDigest: "deadbeef") == nil)        // too short
        #expect(NebulaSSLPinningPin(hexDigest: String(repeating: "z", count: 64)) == nil)  // non-hex
        #expect(NebulaSSLPinningPin(hexDigest: String(repeating: "0", count: 63)) == nil)  // odd length
    }

    @Test func hostPinsEquatableHashable() {
        let pin = NebulaSSLPinningPin(digest: Data(repeating: 1, count: 32))!
        let a = NebulaSSLPinning.HostPins(host: "a", pins: [pin])
        let b = NebulaSSLPinning.HostPins(host: "a", pins: [pin])
        let c = NebulaSSLPinning.HostPins(host: "b", pins: [pin])
        #expect(a == b)
        #expect(a != c)
        #expect(Set([a, b]).count == 1)  // Hashable dedups
    }

    @Test func policyFluentBuildersReturnDistinctCopies() {
        let pin = NebulaSSLPinningPin(digest: Data(repeating: 1, count: 32))!
        let base = NebulaSSLPinning.pins(for: "a.example.com", [pin])
        let withSubs = base.withIncludeSubdomains(true)
        let withFailOpen = base.withFailClosedForUnknownHosts(false)
        let withNoChain = base.withValidateChainFirst(false)
        let withHosts = base.withHostPins([.init(host: "b.example.com", pins: [pin])])
        #expect(base.includeSubdomains == false)
        #expect(withSubs.includeSubdomains == true)
        #expect(withFailOpen.failClosedForUnknownHosts == false)
        #expect(withNoChain.validateChainFirst == false)
        #expect(withHosts.hostPins.first?.host == "b.example.com")
        // Each builder returns a distinct value; the base is unchanged.
        #expect(base != withSubs)
        #expect(base != withHosts)
    }

    @Test func policyAndPinAreSendable() async {
        let pin = NebulaSSLPinningPin(digest: Data(repeating: 1, count: 32))!
        let policy = NebulaSSLPinning.pins(for: "api.example.com", [pin])
        // Send across a Task boundary — compiles only because both are Sendable.
        let roundTrippedPin = await Task { pin }.value
        let roundTrippedPolicy = await Task { policy }.value
        #expect(roundTrippedPin == pin)
        #expect(roundTrippedPolicy == policy)
    }

    // MARK: - B. Host lookup + subdomain walk (the internal helper)

    @Test func resolvedPinsExactMatchWins() {
        let leaf = NebulaSSLPinningPin(digest: Data(repeating: 1, count: 32))!
        let parent = NebulaSSLPinningPin(digest: Data(repeating: 2, count: 32))!
        let policy = NebulaSSLPinning(
            hostPins: [
                .init(host: "example.com", pins: [parent]),
                .init(host: "api.example.com", pins: [leaf])
            ],
            includeSubdomains: true
        )
        let resolved = NebulaSSLPinningEvaluator.resolvedPins(for: "api.example.com", policy: policy)
        #expect(resolved == [leaf])
    }

    @Test func resolvedPinsSubdomainWalk() {
        let parent = NebulaSSLPinningPin(digest: Data(repeating: 2, count: 32))!
        let policy = NebulaSSLPinning(
            hostPins: [.init(host: "example.com", pins: [parent])],
            includeSubdomains: true
        )
        // Walk: a.b.example.com → b.example.com (none) → example.com (match).
        #expect(NebulaSSLPinningEvaluator.resolvedPins(for: "a.b.example.com", policy: policy) == [parent])
        #expect(NebulaSSLPinningEvaluator.resolvedPins(for: "api.example.com", policy: policy) == [parent])
    }

    @Test func resolvedPinsNoSubdomainWalkWhenDisabled() {
        let parent = NebulaSSLPinningPin(digest: Data(repeating: 2, count: 32))!
        let policy = NebulaSSLPinning(
            hostPins: [.init(host: "example.com", pins: [parent])],
            includeSubdomains: false
        )
        #expect(NebulaSSLPinningEvaluator.resolvedPins(for: "api.example.com", policy: policy) == nil)
        #expect(NebulaSSLPinningEvaluator.resolvedPins(for: "example.com", policy: policy) == [parent])
    }

    @Test func resolvedPinsReturnsNilWhenNoHostApplies() {
        let policy = NebulaSSLPinning(hostPins: [], includeSubdomains: true)
        #expect(NebulaSSLPinningEvaluator.resolvedPins(for: "api.example.com", policy: policy) == nil)
    }

    @Test func resolvedPinsDoesNotMatchPublicSuffix() {
        let parent = NebulaSSLPinningPin(digest: Data(repeating: 2, count: 32))!
        // A pin on "com" (single-label) must NOT apply to "api.example.com".
        let policy = NebulaSSLPinning(
            hostPins: [.init(host: "com", pins: [parent])],
            includeSubdomains: true
        )
        #expect(NebulaSSLPinningEvaluator.resolvedPins(for: "api.example.com", policy: policy) == nil)
    }

    @Test func resolvedPinsMatchesCaseInsensitively() {
        // RFC 1035: DNS names are ASCII case-insensitive. A mixed-case stored
        // host must match a differently-cased lookup (and vice-versa).
        let pin = NebulaSSLPinningPin(digest: Data(repeating: 1, count: 32))!
        let policy = NebulaSSLPinning(
            hostPins: [.init(host: "Example.Com", pins: [pin])],
            includeSubdomains: true
        )
        #expect(NebulaSSLPinningEvaluator.resolvedPins(for: "example.com", policy: policy) == [pin])
        #expect(NebulaSSLPinningEvaluator.resolvedPins(for: "EXAMPLE.COM", policy: policy) == [pin])
        #expect(NebulaSSLPinningEvaluator.resolvedPins(for: "api.example.com", policy: policy) == [pin])
        #expect(NebulaSSLPinningEvaluator.resolvedPins(for: "API.Example.Com", policy: policy) == [pin])
    }

    // MARK: - C. SPKI extraction against a synthetic SecTrust
    //
    // The test certificate is a self-signed RSA-2048 cert (CN=test.example.com),
    // generated offline and embedded as a `[UInt8]` literal — no SPM
    // `resources:`, no bundle. The golden pin is the SHA-256 of the cert's
    // public-key DER external representation, computed once via the same
    // Security API path the evaluator uses and hardcoded here.
    //
    // Documented untested branch: the `extractedAny == false` →
    // `.spkiExtractionFailed` path (every cert in the chain fails key/DER
    // extraction) is unreachable with a well-formed cert — `SecCertificateCopyKey`
    // / `SecKeyCopyExternalRepresentation` succeed for any valid cert, and no
    // in-process fixture makes them return nil. It is a defensive branch; the
    // chain-copy-failure path is likewise unreachable with a well-formed trust.

    /// The self-signed RSA test certificate DER (CN=test.example.com).
    private let testCertDER: [UInt8] = [
        0x30, 0x82, 0x02, 0xB2, 0x30, 0x82, 0x01, 0x9A, 0x02, 0x09, 0x00, 0xBA,
        0x3B, 0x05, 0xD4, 0xFA, 0x91, 0x75, 0xC0, 0x30, 0x0D, 0x06, 0x09, 0x2A,
        0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B, 0x05, 0x00, 0x30, 0x1B,
        0x31, 0x19, 0x30, 0x17, 0x06, 0x03, 0x55, 0x04, 0x03, 0x0C, 0x10, 0x74,
        0x65, 0x73, 0x74, 0x2E, 0x65, 0x78, 0x61, 0x6D, 0x70, 0x6C, 0x65, 0x2E,
        0x63, 0x6F, 0x6D, 0x30, 0x1E, 0x17, 0x0D, 0x32, 0x36, 0x30, 0x37, 0x32,
        0x31, 0x30, 0x32, 0x30, 0x31, 0x33, 0x33, 0x5A, 0x17, 0x0D, 0x33, 0x36,
        0x30, 0x37, 0x31, 0x38, 0x30, 0x32, 0x30, 0x31, 0x33, 0x33, 0x5A, 0x30,
        0x1B, 0x31, 0x19, 0x30, 0x17, 0x06, 0x03, 0x55, 0x04, 0x03, 0x0C, 0x10,
        0x74, 0x65, 0x73, 0x74, 0x2E, 0x65, 0x78, 0x61, 0x6D, 0x70, 0x6C, 0x65,
        0x2E, 0x63, 0x6F, 0x6D, 0x30, 0x82, 0x01, 0x22, 0x30, 0x0D, 0x06, 0x09,
        0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03,
        0x82, 0x01, 0x0F, 0x00, 0x30, 0x82, 0x01, 0x0A, 0x02, 0x82, 0x01, 0x01,
        0x00, 0xB9, 0x63, 0x5C, 0xC1, 0x8F, 0x98, 0xA8, 0xFF, 0x0F, 0xF0, 0x53,
        0x40, 0xED, 0x44, 0xFB, 0x06, 0xFF, 0x27, 0x08, 0x49, 0xE0, 0x49, 0x00,
        0x38, 0x59, 0x0F, 0xDD, 0xA1, 0x5E, 0x91, 0x08, 0xC5, 0x57, 0xCC, 0x82,
        0xA0, 0x60, 0x0F, 0x2D, 0x53, 0x8A, 0x66, 0x86, 0xFD, 0xEE, 0xD5, 0x5B,
        0xEF, 0xF9, 0xDF, 0x13, 0x06, 0x39, 0xD0, 0x5F, 0x20, 0xA0, 0x59, 0xAD,
        0xF9, 0xAC, 0xE5, 0x93, 0xF9, 0x25, 0x8A, 0x56, 0x63, 0x32, 0x28, 0xE5,
        0x22, 0xC8, 0x3D, 0xB7, 0x1F, 0xB6, 0x5D, 0x3E, 0x0A, 0x68, 0x28, 0xD5,
        0xAB, 0xDD, 0x88, 0x93, 0x16, 0x2C, 0x0C, 0x44, 0x13, 0xB6, 0x6D, 0x55,
        0xCE, 0x7D, 0xFD, 0x8D, 0x60, 0xFD, 0x34, 0xE1, 0xE6, 0x10, 0x99, 0x95,
        0x65, 0x48, 0x04, 0x8A, 0xD3, 0xD9, 0x72, 0x32, 0x2B, 0xC2, 0x73, 0x00,
        0x1E, 0x5B, 0x59, 0x01, 0xBE, 0x9B, 0xFE, 0x43, 0x07, 0x72, 0xEB, 0xD2,
        0x54, 0x76, 0xFB, 0x23, 0xE5, 0xFC, 0x3F, 0x85, 0x5F, 0xEE, 0x37, 0x41,
        0x11, 0x24, 0x95, 0x57, 0x76, 0xA3, 0x05, 0xC8, 0xDF, 0x85, 0x56, 0x2F,
        0xEF, 0xD6, 0x3D, 0x8F, 0x96, 0x54, 0xB1, 0x67, 0x72, 0xAC, 0xE9, 0xE2,
        0x94, 0x4E, 0x31, 0x7F, 0x8F, 0x75, 0x8C, 0xBB, 0xC2, 0x98, 0x49, 0x73,
        0x93, 0x44, 0xBB, 0x1A, 0x25, 0xFB, 0xCA, 0x78, 0x12, 0x82, 0x1F, 0x3A,
        0xA7, 0x1A, 0x8A, 0x11, 0x9E, 0x11, 0x18, 0x23, 0x82, 0xBB, 0x0B, 0xD6,
        0x64, 0x5C, 0x49, 0x3D, 0x87, 0x5A, 0xB5, 0x9B, 0x0C, 0x73, 0x63, 0x01,
        0x88, 0xBC, 0xAA, 0x7B, 0x76, 0xE6, 0x66, 0x7A, 0x2C, 0x87, 0xE5, 0x0E,
        0xDC, 0xD4, 0x5A, 0xD1, 0x1E, 0xFD, 0x8A, 0x2A, 0xBD, 0x94, 0x30, 0x48,
        0x79, 0xEA, 0xD1, 0x32, 0x33, 0x5A, 0xF2, 0xB9, 0x5A, 0xD5, 0x56, 0xF0,
        0xB4, 0xBE, 0x11, 0xC5, 0x1D, 0x02, 0x03, 0x01, 0x00, 0x01, 0x30, 0x0D,
        0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B, 0x05,
        0x00, 0x03, 0x82, 0x01, 0x01, 0x00, 0x63, 0x6D, 0x5F, 0xBF, 0xE1, 0x99,
        0xA4, 0x1C, 0x0C, 0x47, 0x4B, 0x08, 0x39, 0x72, 0xF2, 0xFD, 0xB9, 0x91,
        0xF8, 0x57, 0x04, 0x17, 0xC4, 0xFD, 0x1D, 0x3A, 0x39, 0xF4, 0x77, 0x42,
        0xC9, 0x5D, 0x6A, 0xDA, 0xCA, 0xE7, 0x55, 0xE9, 0xD6, 0xBD, 0x87, 0x0A,
        0xE5, 0xA7, 0x4C, 0xEC, 0xB2, 0x91, 0x04, 0xA7, 0x39, 0xA6, 0x24, 0xBB,
        0x98, 0x45, 0x4C, 0xCD, 0x02, 0x3C, 0x86, 0xF1, 0xDD, 0x1C, 0x90, 0xD6,
        0x65, 0xCA, 0xB2, 0xBB, 0xDB, 0x0F, 0x6F, 0x2A, 0x10, 0x19, 0x18, 0x77,
        0xC2, 0x63, 0xC5, 0x35, 0x45, 0x28, 0xD2, 0x1F, 0x5C, 0x95, 0x88, 0xD6,
        0x0B, 0x55, 0xA1, 0x66, 0x14, 0xF5, 0x5E, 0x45, 0xB5, 0x9C, 0x5D, 0x4B,
        0xDB, 0x9B, 0x66, 0x6C, 0xAC, 0xAC, 0xB6, 0xBB, 0xB6, 0xB4, 0x40, 0x98,
        0x29, 0xA3, 0xFF, 0x58, 0xE0, 0x90, 0x4B, 0xC0, 0xDD, 0xCF, 0xE0, 0xAA,
        0xC3, 0x1A, 0x4D, 0xDC, 0x42, 0x8C, 0x96, 0x30, 0x5D, 0x3C, 0x20, 0x8B,
        0x2E, 0x0A, 0x16, 0x1C, 0x2B, 0x7C, 0x37, 0x38, 0xAA, 0xB7, 0x9D, 0x38,
        0x61, 0x65, 0x51, 0x16, 0x1E, 0xF2, 0x25, 0x2C, 0x88, 0xAB, 0xA5, 0x44,
        0x82, 0x67, 0x45, 0x03, 0xFB, 0x68, 0x0C, 0x2F, 0xB5, 0xB0, 0x0D, 0xDF,
        0x21, 0xFB, 0xCF, 0xF8, 0xBB, 0x45, 0x4F, 0x63, 0x8A, 0x1D, 0xEB, 0xA5,
        0x83, 0xC4, 0x69, 0x98, 0x39, 0x54, 0x41, 0x3F, 0x7F, 0x27, 0x87, 0x99,
        0x91, 0x1D, 0x16, 0xEA, 0x1D, 0x0E, 0x8A, 0xF7, 0xAB, 0xDD, 0x17, 0xF0,
        0x42, 0x99, 0xA6, 0xC8, 0xF4, 0x9E, 0x7D, 0x43, 0x75, 0xCA, 0xCB, 0x54,
        0x51, 0x63, 0x98, 0x88, 0x19, 0x19, 0x83, 0x8F, 0x26, 0x51, 0xCE, 0x46,
        0x9B, 0xF3, 0x2F, 0x48, 0xD2, 0x55, 0xD4, 0xB3, 0x79, 0x20, 0x79, 0x44,
        0xDF, 0x07, 0x84, 0x23, 0xA5, 0x24, 0x68, 0x7D, 0x07, 0x65
    ]

    /// The golden pin: SHA-256 of the test cert's public-key DER.
    private let goldenPinHex = "7badc2c8e548c45f08e381188ad1aa7fae4addc57eb8aee78f17478482ad3b2a"

    /// Builds a synthetic `SecTrust` for the test cert (CN=test.example.com).
    private func makeTrust(host: String = "test.example.com") -> SecTrust {
        let cert = SecCertificateCreateWithData(nil, Data(testCertDER) as CFData)!
        let sslPolicy = SecPolicyCreateSSL(true, host as CFString)
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(cert, sslPolicy, &trust)
        #expect(status == errSecSuccess)
        return trust!
    }

    @Test func evaluateMatchesGoldenPinWhenChainCheckSkipped() {
        let golden = NebulaSSLPinningPin(hexDigest: goldenPinHex)!
        let policy = NebulaSSLPinning.pins(for: "test.example.com", [golden])
            .withValidateChainFirst(false)  // self-signed cert fails OS trust
        let result = NebulaSSLPinningEvaluator.evaluate(trust: makeTrust(), host: "test.example.com", policy: policy)
        guard case .matched(let pin, let index) = result else {
            Issue.record("expected .matched, got \(result)")
            return
        }
        #expect(pin == golden)
        #expect(index == 0)
    }

    @Test func evaluateNoMatchingPinForWrongPin() {
        let wrong = NebulaSSLPinningPin(digest: Data(repeating: 0x99, count: 32))!
        let policy = NebulaSSLPinning.pins(for: "test.example.com", [wrong])
            .withValidateChainFirst(false)
        let result = NebulaSSLPinningEvaluator.evaluate(trust: makeTrust(), host: "test.example.com", policy: policy)
        #expect(result == .noMatchingPin)
    }

    @Test func evaluateNoPinForHostWhenPolicyEmpty() {
        let policy = NebulaSSLPinning(hostPins: [], validateChainFirst: false)
        let result = NebulaSSLPinningEvaluator.evaluate(trust: makeTrust(), host: "test.example.com", policy: policy)
        #expect(result == .noPinForHost)
    }

    @Test func evaluateChainValidationFailsForSelfSignedByDefault() {
        // validateChainFirst defaults to true → the self-signed cert is
        // rejected by the OS trust store before pin matching.
        let golden = NebulaSSLPinningPin(hexDigest: goldenPinHex)!
        let policy = NebulaSSLPinning.pins(for: "test.example.com", [golden])  // default validateChainFirst: true
        let result = NebulaSSLPinningEvaluator.evaluate(trust: makeTrust(), host: "test.example.com", policy: policy)
        guard case .chainValidationFailed = result else {
            Issue.record("expected .chainValidationFailed, got \(result)")
            return
        }
    }

    @Test func evaluateSubdomainMatch() {
        let golden = NebulaSSLPinningPin(hexDigest: goldenPinHex)!
        // Pin configured for the parent; the request host is a subdomain.
        let policy = NebulaSSLPinning(
            hostPins: [.init(host: "example.com", pins: [golden])],
            includeSubdomains: true,
            validateChainFirst: false
        )
        let result = NebulaSSLPinningEvaluator.evaluate(trust: makeTrust(), host: "api.example.com", policy: policy)
        guard case .matched(let pin, _) = result else {
            Issue.record("expected .matched via subdomain walk, got \(result)")
            return
        }
        #expect(pin == golden)
    }

    // MARK: - D. Disposition (the delegate's testable seam)

    @Test func dispositionMatchedUsesCredential() {
        let golden = NebulaSSLPinningPin(hexDigest: goldenPinHex)!
        let delegate = NebulaURLSessionDelegate(
            pinning: .pins(for: "test.example.com", [golden]).withValidateChainFirst(false)
        )
        let trust = makeTrust()
        let (disposition, credential) = delegate.disposition(
            for: .matched(pin: golden, certificateIndex: 0),
            policy: delegate.pinning,
            trust: trust
        )
        #expect(disposition == .useCredential)
        #expect(credential != nil)
    }

    @Test func dispositionNoPinForHostFailClosed() {
        let policy = NebulaSSLPinning(hostPins: [], failClosedForUnknownHosts: true)
        let delegate = NebulaURLSessionDelegate(pinning: policy)
        let (disposition, credential) = delegate.disposition(
            for: .noPinForHost, policy: policy, trust: makeTrust()
        )
        #expect(disposition == .cancelAuthenticationChallenge)
        #expect(credential == nil)
    }

    @Test func dispositionNoPinForHostFailOpen() {
        let policy = NebulaSSLPinning(hostPins: [], failClosedForUnknownHosts: false)
        let delegate = NebulaURLSessionDelegate(pinning: policy)
        let (disposition, credential) = delegate.disposition(
            for: .noPinForHost, policy: policy, trust: makeTrust()
        )
        #expect(disposition == .performDefaultHandling)
        #expect(credential == nil)
    }

    @Test func dispositionFailuresCancel() {
        let policy = NebulaSSLPinning(hostPins: [])
        let delegate = NebulaURLSessionDelegate(pinning: policy)
        let trust = makeTrust()
        for result in [NebulaSSLPinningResult.noMatchingPin,
                       .chainValidationFailed(message: "x"),
                       .spkiExtractionFailed(message: "y")] {
            let (disposition, credential) = delegate.disposition(for: result, policy: policy, trust: trust)
            #expect(disposition == .cancelAuthenticationChallenge)
            #expect(credential == nil)
        }
    }

    @Test func sessionBuilderReturnsPinnedSession() {
        let pin = NebulaSSLPinningPin(digest: Data(repeating: 1, count: 32))!
        let pinned = NebulaHTTPSession.pinned(by: .pins(for: "api.example.com", [pin]))
        #expect(pinned.session.delegate is NebulaURLSessionDelegate)
        #expect((pinned.session.delegate as? NebulaURLSessionDelegate)?.pinning.hostPins.first?.host == "api.example.com")
        #expect(pinned.delegate.pinning.hostPins.first?.host == "api.example.com")
    }

    // MARK: - Error

    @Test func errorFactoryStaticsAndCoarseKind() {
        let noMatch = NebulaSSLPinningError.noMatchingPin()
        #expect(noMatch.kind == .noMatchingPin)
        #expect(noMatch.code == "no-matching-pin")
        #expect(noMatch.coarseKind == .network)

        let chainFail = NebulaSSLPinningError.chainValidationFailed("bad", underlying: nil)
        #expect(chainFail.coarseKind == .network)

        let cancelled = NebulaSSLPinningError.cancelled()
        #expect(cancelled.coarseKind == .unknown)
    }

    @Test func errorBridgesToNebulaError() {
        let error = NebulaSSLPinningError.noPinForHost()
        let nebula = error.toNebulaError(kind: .network)
        #expect(nebula.code.domain == "Nebula.NebulaSSLPinningError")
        #expect(nebula.kind == .network)
        #expect(nebula.metadata["NebulaCode"] == "no-pin-for-host")
    }

    @Test func errorSendable() async {
        let error = NebulaSSLPinningError.noMatchingPin()
        let roundTripped = await Task { error }.value
        #expect(roundTripped == error)
    }
}
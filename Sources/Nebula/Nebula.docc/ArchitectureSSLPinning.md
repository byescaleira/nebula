# SSL/TLS public-key pinning

A `Sendable` pinning policy, a pure trust evaluator, and a `URLSessionDelegate` façade that hardens ``NebulaHTTPGateway`` against man-in-the-middle certificate substitution — with **zero gateway changes**.

## Overview

``NebulaHTTPGateway`` already accepts an opaque `session: URLSession`, so pinning plugs in at the transport layer where it belongs: a caller injects a `URLSession` whose delegate evaluates server trust against a ``NebulaSSLPinning`` policy. Pinning is **not** an ``NebulaHTTPInterceptor`` — a pinning failure surfaces as a `URLError` from the `URLSession` *before/under* the `data(for:)` call, so trust evaluation has to happen at the `URLSessionDelegate` layer; an `adapt`/`retry` interceptor only mutates the `URLRequest` and reacts to thrown errors, it cannot evaluate trust. The interceptor surface shipped in N10; N17a adds pinning as a separate transport concern.

```swift
let pin = NebulaSSLPinningPin(hexDigest: "d6d4c…")!          // SHA-256 of the cert's public-key DER
let policy = NebulaSSLPinning.pins(for: "api.example.com", [pin])
    .withIncludeSubdomains(true)
let pinned = NebulaHTTPSession.pinned(by: policy)
let gateway = NebulaHTTPGateway(
    .init(endpoint: URL(string: "https://api.example.com")!),
    session: pinned.session
)
```

Three types compose the surface:

- ``NebulaSSLPinning`` — the `Sendable` **policy**: per-host SPKI SHA-256 pin sets plus options. Pure data; no `URLSession`, no `SecTrust`.
- ``NebulaSSLPinningEvaluator`` — the **pure trust evaluator**: a `static` function over a `SecTrust` + host + policy, returning a ``NebulaSSLPinningResult``. Reusable outside `URLSession`.
- ``NebulaURLSessionDelegate`` — the **`@objc` delegate façade**: a `final class : NSObject, URLSessionDelegate, Sendable` that evaluates server-trust challenges and maps the result to a disposition. Held by the `URLSession`; built via ``NebulaHTTPSession/pinned(by:configuration:logger:)``.

### Why a policy / evaluator / delegate split

The split is the testability lever. The evaluator is a pure function over a `SecTrust`, so it is unit-testable on the macOS host with a **synthetic `SecTrust`** built from a self-signed test certificate embedded as a `[UInt8]` literal — no live TLS server, no `URLSession`. The delegate's only logic is the disposition mapping, factored as the `internal` ``NebulaURLSessionDelegate/disposition(for:policy:trust:)`` helper (a `URLProtectionSpace` with a non-nil `serverTrust` cannot be built via the public init, so the delegate method itself is not round-trip unit-tested — the evaluator + disposition cover the logic completely). The policy is pure data, so its value semantics and the host lookup are testable without any Security types.

## Policy

``NebulaSSLPinning`` carries per-host pin sets (``NebulaSSLPinning/HostPins``) and four options, with fluent `.with*` builders mirroring ``NebulaGatewayConfiguration``:

- ``NebulaSSLPinning/includeSubdomains`` (default `false`) — when `true`, a host with no exact entry is matched by walking parent domains (`api.example.com` → `example.com`), stopping before the single-label public suffix.
- ``NebulaSSLPinning/validateChainFirst`` (default `true`) — run `SecTrustEvaluateWithError` first; a chain the OS trust store rejects fails before pin matching.
- ``NebulaSSLPinning/failClosedForUnknownHosts`` (default `true`) — a host with no applicable pin fails closed (the challenge is cancelled); `false` falls through to `URLSession`'s default handling (no pin enforcement).

A pin (``NebulaSSLPinningPin``) is the 32-byte SHA-256 digest of a certificate's public-key DER external representation. Construct from raw bytes (``NebulaSSLPinningPin/init(digest:)``) or a 64-char hex string (``NebulaSSLPinningPin/init(hexDigest:)``); round-trip via ``NebulaSSLPinningPin/hexDigest``.

## Evaluator

``NebulaSSLPinningEvaluator/evaluate(trust:host:policy:)`` runs the OWASP "any position" SPKI algorithm, additive to system trust:

1. If `policy.validateChainFirst`, run `SecTrustEvaluateWithError`; an OS-rejected chain → ``NebulaSSLPinningResult/chainValidationFailed(message:)``.
2. Resolve the pin set for `host` (exact match, then a parent-domain walk when `includeSubdomains`); no applicable pin → ``NebulaSSLPinningResult/noPinForHost``. Host matching is **case-insensitive** (RFC 1035 — `host` and the stored ``NebulaSSLPinning/HostPins/host`` are both `.lowercased()` before comparison; stored data is not mutated).
3. Copy the certificate chain via `SecTrustCopyCertificateChain`.
4. For each cert, extract its public key (`SecCertificateCopyKey`), its DER external representation (`SecKeyCopyExternalRepresentation`), and SHA-256 it (`Data.nebulaDigest(of: .sha256)`); a digest in the pin set → ``NebulaSSLPinningResult/matched(pin:certificateIndex:)``. Matching **any** cert in the chain (leaf or intermediate/CA) survives leaf rotation. A single un-extractable key is skipped (not fatal).
5. If no cert matched but at least one SPKI was extracted → ``NebulaSSLPinningResult/noMatchingPin``; if **every** cert failed key/DER extraction (or the chain could not be copied) → ``NebulaSSLPinningResult/spkiExtractionFailed(message:)`` — a truthful diagnostic for a caller bridging to ``NebulaSSLPinningError``.

The SHA-256 goes through the existing `Data.nebulaDigest(of:)` extension → ``NebulaHashAlgorithm``/sha256 → `CryptoKit.SHA256` — **no new `import CryptoKit`** (the only file that imports CryptoKit is `NebulaHashAlgorithm.swift`).

## Delegate

``NebulaURLSessionDelegate`` is a `final class : NSObject, URLSessionDelegate, Sendable`. `Sendable` is **derived** — the only stored properties are the immutable `let pinning: NebulaSSLPinning` and `let logger: NebulaLogger?` (both Sendable); **no `@unchecked`**. `URLSessionDelegate` is annotated `NS_SWIFT_SENDABLE`, so conformance to a Sendable `@objc` protocol does not block derived `Sendable` on a `final` class whose only stored props are immutable `let`s of Sendable type. This matches the ``NebulaUNNotificationCenter`` precedent.

The delegate does **not** throw (the `@objc optional` method has no `throws`). On a pinning failure it logs (if a ``NebulaLogger`` is set) and calls the completion with `.cancelAuthenticationChallenge`; `URLSession` then surfaces a `URLError` to ``NebulaHTTPGateway``, which already bridges `URLError → NebulaError(urlError:)`. **No gateway change, no new bridge wired.**

## Session builder

``NebulaHTTPSession/pinned(by:configuration:logger:)`` returns a ``NebulaPinnedSession`` carrying both the `URLSession` and the delegate. `URLSession` does **not** strongly retain its delegate, so the builder returns both — retaining the `NebulaPinnedSession` value is sufficient for the delegate's lifetime. An `enum` namespace (no instances) avoids extending `URLSession` (which would collide stylistically with `URLSession.shared` / `URLSession(configuration:)`). No process-wide accessor — pinning is per-session, unlike logging/measurement.

## Errors

``NebulaSSLPinningError`` is an open-struct error mirroring ``NebulaHTTPServerError``: an extensible ``NebulaSSLPinningError/Kind`` (a string literal — new categories need no library release) plus the coarse ``NebulaError/Kind`` mapping and the ``NebulaSSLPinningError/toNebulaError(kind:)`` bridge. **No new ``NebulaError/Kind`` case** is added. The live gateway path does not surface this error (it surfaces the `URLError`); ``NebulaSSLPinningError`` exists for non-`URLSession` consumers of the evaluator and for the delegate's logger diagnostics.

## Security note

Pinning is **additive to system trust**: ``NebulaSSLPinning/validateChainFirst`` defaults to `true`, so the OS trust store is evaluated first and pinning only adds a constraint on top — it never replaces the OS anchors. Carry a **backup pin** (OWASP guidance) so a certificate rotation does not lock out the app. `SecTrustEvaluateWithError` may perform a network fetch (OCSP / intermediate) inside the URLSession delegate queue; for offline-only pinning set `validateChainFirst` to `false` to rely solely on pin matching. Pinning is enforced per-session via the injected delegate — a `URLSession.shared`-backed gateway is **not** pinned.

## Testability note

The live `URLSession` + delegate round-trip over real TLS is **not** exercised by the unit suite — `URLProtectionSpace.serverTrust` is `nil` unless the system created the space during a real handshake, and a real TLS server harness is out of scope for a Foundation-only SPM test target. The evaluator is unit-tested with a synthetic `SecTrust` built from a self-signed RSA test cert embedded as a `[UInt8]` literal (no SPM `resources:`), and the disposition mapping is unit-tested directly. This mirrors the ``NebulaUNNotificationCenter`` precedent (a delegate that cannot be round-trip-tested headlessly).

## Topics

### Policy
- ``NebulaSSLPinning``
- ``NebulaSSLPinning/HostPins``
- ``NebulaSSLPinning/init(hostPins:includeSubdomains:validateChainFirst:failClosedForUnknownHosts:)``
- ``NebulaSSLPinning/pins(for:_:)``
- ``NebulaSSLPinning/withHostPins(_:)``
- ``NebulaSSLPinning/withIncludeSubdomains(_:)``
- ``NebulaSSLPinning/withValidateChainFirst(_:)``
- ``NebulaSSLPinning/withFailClosedForUnknownHosts(_:)``
- ``NebulaSSLPinningPin``
- ``NebulaSSLPinningPin/init(digest:)``
- ``NebulaSSLPinningPin/init(hexDigest:)``
- ``NebulaSSLPinningPin/hexDigest``

### Evaluator
- ``NebulaSSLPinningEvaluator``
- ``NebulaSSLPinningEvaluator/evaluate(trust:host:policy:)``
- ``NebulaSSLPinningResult``

### Delegate
- ``NebulaURLSessionDelegate``
- ``NebulaURLSessionDelegate/init(pinning:logger:)``
- ``NebulaURLSessionDelegate/pinning``
- ``NebulaURLSessionDelegate/logger``

### Session builder
- ``NebulaHTTPSession``
- ``NebulaHTTPSession/pinned(by:configuration:logger:)``
- ``NebulaPinnedSession``

### Error
- ``NebulaSSLPinningError``
- ``NebulaSSLPinningError/Kind``
- ``NebulaSSLPinningError/coarseKind``
- ``NebulaSSLPinningError/toNebulaError(kind:)``

<!-- Copyright (c) 2026 Nebula. All rights reserved. -->
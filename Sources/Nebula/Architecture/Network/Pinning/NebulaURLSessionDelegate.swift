//
//  NebulaURLSessionDelegate.swift
//  Nebula
//
//  Wave N17a — Network hardening. The `URLSessionDelegate` façade for SSL/TLS
//  public-key pinning: a `final class : NSObject, URLSessionDelegate, Sendable`
//  that evaluates server-trust challenges against a ``NebulaSSLPinning``
//  policy and calls the completion handler with `.useCredential` (matched) or
//  `.cancelAuthenticationChallenge` (failed / fail-closed). Non-server-trust
//  challenges fall through to `.performDefaultHandling`.
//
//  `Sendable` is **derived** — the only stored properties are the immutable
//  `let pinning: NebulaSSLPinning` (a Sendable value) and `let logger:
//  NebulaLogger?` (Sendable). NO `@unchecked`. This matches the
//  ``NebulaUNNotificationCenter`` precedent (`final class : NSObject, …,
//  Sendable`, derived — the `@objc` delegate protocol `URLSessionDelegate` is
//  annotated `NS_SWIFT_SENDABLE`, so conformance to a Sendable `@objc`
//  protocol does not block derived `Sendable` on a `final` class whose only
//  stored props are immutable `let`s of Sendable type). Probed against the
//  Xcode 27 Beta 3 SDK with `swiftc -typecheck -swift-version 6
//  -strict-concurrency=complete -warnings-as-errors` → EXIT=0, zero warnings.
//
//  NSObject base: `URLSessionDelegate` is an `@objc` protocol with `@objc
//  optional` methods, so the conforming class must be Obj-C-runtime-dispatched
//  — the ``NebulaUNNotificationCenter`` precedent establishes NSObject for
//  `@objc` delegate protocols in Nebula. No UIKit (NSObject is Foundation).
//
//  The delegate does NOT throw (`@objc optional` method has no `throws`). On a
//  pinning failure it logs (if `logger` set) and calls
//  `.cancelAuthenticationChallenge`; `URLSession` then surfaces a `URLError`
//  to ``NebulaHTTPGateway``, which already bridges `URLError →
//  NebulaError(urlError:)` — **no gateway change, no new bridge wired**.
//
//  Testability: the `urlSession(_:didReceive:completionHandler:)` body is a
//  thin guard → evaluate → map → completion. The map is the `internal`
//  ``disposition(for:policy:trust:)`` helper, which is unit-tested directly
//  (a `URLProtectionSpace` with a non-nil `serverTrust` cannot be built via
//  the public init, so the delegate method itself is not round-trip
//  unit-tested — the evaluator + disposition cover the logic). See
//  vault/03-padroes/nebula-ssl-pinning.md.
//

import Foundation
import Security

/// A `final class : NSObject, URLSessionDelegate, Sendable` that evaluates
/// server-trust challenges against a ``NebulaSSLPinning`` policy.
///
/// Attach it to a `URLSession` via `URLSession(configuration:delegate:delegateQueue:)`
/// — or use the ``NebulaHTTPSession/pinned(by:configuration:logger:)`` builder,
/// which returns a ``NebulaPinnedSession`` carrying both the session and this
/// delegate (the caller must retain the delegate: `URLSession` does NOT
/// strongly retain its delegate).
public final class NebulaURLSessionDelegate: NSObject, URLSessionDelegate, Sendable {

    /// The pinning policy.
    public let pinning: NebulaSSLPinning

    /// An optional logger for pinning diagnostics (`nil` = silent).
    public let logger: NebulaLogger?

    /// Creates the delegate.
    public init(pinning: NebulaSSLPinning, logger: NebulaLogger? = nil) {
        self.pinning = pinning
        self.logger = logger
        super.init()
    }

    // MARK: - URLSessionDelegate

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = space.serverTrust else {
            // Not a server-trust challenge — let URLSession handle it.
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let result = NebulaSSLPinningEvaluator.evaluate(trust: trust, host: space.host, policy: pinning)
        if case .matched = result {
            // Success — no diagnostic.
        } else {
            logger?.log(.error, "Nebula pinning failed for \(space.host): \(result)")
        }
        let (disposition, credential) = disposition(for: result, policy: pinning, trust: trust)
        completionHandler(disposition, credential)
    }

    // MARK: - Disposition (the testable seam)
    //
    // The `urlSession(_:didReceive:completionHandler:)` body is a thin
    // guard → evaluate → map → completion. This helper holds the ONLY
    // delegate-side logic (mapping a result to a disposition + credential),
    // and is `internal` so the test module covers it without constructing a
    // `URLAuthenticationChallenge` (whose `serverTrust` is not injectable via
    // the public `URLProtectionSpace` init).

    /// Maps an evaluation `result` to the `(disposition, credential)` pair the
    /// completion handler receives.
    internal func disposition(
        for result: NebulaSSLPinningResult,
        policy: NebulaSSLPinning,
        trust: SecTrust
    ) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        switch result {
        case .matched:
            return (.useCredential, URLCredential(trust: trust))
        case .noPinForHost:
            return policy.failClosedForUnknownHosts
                ? (.cancelAuthenticationChallenge, nil)
                : (.performDefaultHandling, nil)
        case .noMatchingPin, .chainValidationFailed, .spkiExtractionFailed:
            return (.cancelAuthenticationChallenge, nil)
        }
    }
}
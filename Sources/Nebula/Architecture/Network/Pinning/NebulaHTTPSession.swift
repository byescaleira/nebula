//
//  NebulaHTTPSession.swift
//  Nebula
//
//  Wave N17a — Network hardening. The pinned-session builder: a tiny `enum`
//  namespace + a `Sendable` value carrying the constructed `URLSession` and
//  its ``NebulaURLSessionDelegate``. The caller composes a pinned
//  ``NebulaHTTPGateway`` with zero gateway changes — the gateway already
//  accepts an opaque `session: URLSession`:
//
//  ```swift
//  let pinned = NebulaHTTPSession.pinned(by: policy)
//  let gateway = NebulaHTTPGateway(.init(endpoint: URL(string: "https://api.test")!),
//                                  session: pinned.session)
//  ```
//
//  Ownership: `URLSession` does NOT strongly retain its delegate, so
//  ``NebulaHTTPSession/pinned(by:configuration:logger:)`` returns BOTH the
//  session and the delegate in a ``NebulaPinnedSession`` — the caller retains
//  the pair (retaining the `NebulaPinnedSession` value is sufficient; the
//  delegate lives as long as the value does). An `enum` namespace (no
//  instances) matches Nebula's no-stdlib-collision convention — extending
//  `URLSession` with a `pinned(by:)` static would collide stylistically with
//  `URLSession.shared` / `URLSession(configuration:)`. No process-wide
//  accessor (pinning is per-session, unlike logging/measurement).
//
//  Foundation-only here — the `Sec*` evaluation lives in
//  ``NebulaSSLPinningEvaluator`` / ``NebulaURLSessionDelegate``. See
//  vault/03-padroes/nebula-ssl-pinning.md.
//

import Foundation

/// A `URLSession` paired with the ``NebulaURLSessionDelegate`` that owns its
/// pinning evaluation.
///
/// `Sendable` is derived — both fields are `Sendable` (`URLSession` is
/// `Sendable`; the delegate derives `Sendable`). Retain this value (or both
/// fields) for the session's lifetime: `URLSession` does NOT strongly retain
/// its delegate, so dropping the delegate silently disables pinning.
public struct NebulaPinnedSession: Sendable {

    /// The pinned `URLSession`.
    public let session: URLSession

    /// The delegate evaluating server trust against the policy.
    public let delegate: NebulaURLSessionDelegate

    /// Creates the pair.
    public init(session: URLSession, delegate: NebulaURLSessionDelegate) {
        self.session = session
        self.delegate = delegate
    }
}

/// Convenience builders for `URLSession` instances wired with Nebula pinning
/// delegates.
public enum NebulaHTTPSession {

    /// Creates a `URLSession` whose delegate evaluates server trust against
    /// `pinning`, returning the session and delegate together as a
    /// ``NebulaPinnedSession``.
    ///
    /// - Parameters:
    ///   - pinning: the pinning policy.
    ///   - configuration: the session configuration (default `.ephemeral` — a
    ///     pinning session typically does not share the global cookie/cache
    ///     store; pass `.default` if you need it).
    ///   - logger: an optional logger for pinning diagnostics.
    public static func pinned(
        by pinning: NebulaSSLPinning,
        configuration: URLSessionConfiguration = .ephemeral,
        logger: NebulaLogger? = nil
    ) -> NebulaPinnedSession {
        let delegate = NebulaURLSessionDelegate(pinning: pinning, logger: logger)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        return NebulaPinnedSession(session: session, delegate: delegate)
    }
}
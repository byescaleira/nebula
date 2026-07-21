//
//  NebulaHTTPInterceptor.swift
//  Nebula
//
//  Wave N10 — Network. The interceptor seam: a ``NebulaHTTPInterceptor`` port
//  (``adapt``/``retry``) that can mutate a ``NebulaHTTPEndpoint`` before it is
//  sent and decide whether a failed send should be retried with a fresh
//  endpoint. The existing ``NebulaRetry/withPolicy`` seam re-invokes a captured
//  `() async throws -> T` closure with no input parameter, so it cannot mutate
//  the request between attempts (e.g. inject a refreshed `Authorization`
//  header after a 401) — this port fills that gap. ``NebulaHTTPInterceptorChain``
//  composes interceptors; ``NebulaInterceptedClient`` wraps a
//  ``NebulaHTTPClient`` so the adapted/retried send flows through the chain; the
//  ``NebulaHTTPClient/intercepted(by:)`` default extension wires it in.
//  Foundation-only (no new framework import). See
//  vault/03-padroes/nebula-auth-interceptor.md.
//

import Foundation

/// A request/response interceptor: a `Sendable` hook that can adapt an
/// endpoint before it is sent and decide whether a failed send should be
/// retried with a fresh endpoint.
///
/// The **port** for cross-cutting request concerns (auth-token injection,
/// signing, header enrichment, 401 refresh-and-retry). The pair of methods
/// mirrors the two classic interceptor phases:
/// - ``adapt(_:)`` runs **before** every send and may return a transformed
///   ``NebulaHTTPEndpoint`` (e.g. one carrying an `Authorization` header).
/// - ``retry(_:for:attempt:)`` runs **after** a send throws: return a fresh
///   endpoint to retry the send with, or `nil` to decline (let the error
///   surface). Throwing aborts the retry pass and surfaces that error instead —
///   used by ``NebulaAuthInterceptor`` to surface a refresh failure in place of
///   the 401. `attempt` is the retry index (`0` = the first retry).
///
/// Interceptors are composed left-to-right by ``NebulaHTTPInterceptorChain``,
/// which adapts in order, sends once, and on failure offers each interceptor a
/// single retry chance (retry-once) built from the **original** endpoint — so
/// an interceptor that wraps its input never double-wraps on retry.
public protocol NebulaHTTPInterceptor: Sendable {
    /// Adapts `endpoint` before it is sent. Return the endpoint unchanged to
    /// pass it through. Runs once per send, in chain order.
    func adapt(_ endpoint: NebulaHTTPEndpoint) async throws -> NebulaHTTPEndpoint

    /// Offers the interceptor a chance to retry after `error`. Return a fresh
    /// endpoint to retry the send with, or `nil` to decline. Throw to abort the
    /// retry pass and surface that error instead. `attempt` is the retry index
    /// (`0` = the first retry); the chain offers a single retry pass.
    func retry(_ error: any Error, for endpoint: NebulaHTTPEndpoint, attempt: Int) async throws -> NebulaHTTPEndpoint?
}

// MARK: - Chain

/// A composable, ordered list of ``NebulaHTTPInterceptor``s applied to a
/// ``NebulaHTTPClient`` send.
///
/// `Sendable` by derived conformance — the stored `[any NebulaHTTPInterceptor]`
/// is `Sendable` (the protocol requires it); no `@unchecked`. Not `Equatable`
/// (the interceptor protocol is not `Equatable`). Use ``withInterceptor(_:)``
/// to append and build a new chain (immutable after init, mirroring the
/// `NebulaGatewayConfiguration` shape).
public struct NebulaHTTPInterceptorChain: Sendable {
    /// The interceptors, applied in order.
    public let interceptors: [any NebulaHTTPInterceptor]

    /// Creates a chain. Defaults to empty (a no-op chain forwards `send`
    /// unchanged and never retries).
    public init(_ interceptors: [any NebulaHTTPInterceptor] = []) {
        self.interceptors = interceptors
    }

    /// Returns a new chain with `interceptor` appended.
    public func withInterceptor(_ interceptor: any NebulaHTTPInterceptor) -> NebulaHTTPInterceptorChain {
        NebulaHTTPInterceptorChain(interceptors + [interceptor])
    }

    /// Sends `endpoint` through `client`, applying each interceptor's
    /// ``adapt(_:)`` in order, then — on failure — offering each a single
    /// retry chance built from the original endpoint. `CancellationError` is
    /// never retried (it propagates raw, mirroring ``NebulaHTTPGateway``).
    func send(_ endpoint: NebulaHTTPEndpoint, through client: NebulaHTTPClient) async throws -> NebulaHTTPResponse {
        var adapted = endpoint
        for interceptor in interceptors {
            adapted = try await interceptor.adapt(adapted)
        }
        do {
            return try await client.send(adapted)
        } catch {
            // Cancellation is a client-side action, not a retryable failure.
            if error is CancellationError { throw error }
            // Build the retry from the ORIGINAL endpoint so an interceptor that
            // wraps its input does not double-wrap on retry.
            var retried = endpoint
            var didRetry = false
            for interceptor in interceptors {
                if let next = try await interceptor.retry(error, for: retried, attempt: 0) {
                    retried = next
                    didRetry = true
                }
            }
            if didRetry {
                return try await client.send(retried)
            }
            throw error
        }
    }
}

// MARK: - Composed client

/// A ``NebulaHTTPClient`` that routes its ``send(_:)`` through a
/// ``NebulaHTTPInterceptorChain``, transparently applying adapt/retry to a
/// wrapped client.
///
/// `Sendable` by derived conformance — both stored properties (the wrapped
/// `any NebulaHTTPClient` and the chain) are `Sendable`; no `@unchecked`. The
/// codec requirements (`decoder` / `encoder`) forward to the wrapped client so
/// the verb conveniences encode/decode with the **configured** codecs.
public struct NebulaInterceptedClient: NebulaHTTPClient {
    /// The wrapped client that performs the actual transport.
    public let client: NebulaHTTPClient
    /// The interceptor chain applied to every send.
    public let chain: NebulaHTTPInterceptorChain

    /// Creates an intercepted client.
    public init(_ client: NebulaHTTPClient, chain: NebulaHTTPInterceptorChain) {
        self.client = client
        self.chain = chain
    }

    public var decoder: NebulaJSONDecoder { client.decoder }
    public var encoder: NebulaJSONEncoder { client.encoder }

    public func send(_ endpoint: NebulaHTTPEndpoint) async throws -> NebulaHTTPResponse {
        try await chain.send(endpoint, through: client)
    }
}

public extension NebulaHTTPClient {
    /// Wraps this client so every ``send(_:)`` flows through `chain` (adapt
    /// before send, retry-once on failure). The returned client is a
    /// ``NebulaHTTPClient``, so the verb conveniences (`get`/`post`/…) and the
    /// generic decode work unchanged through the interceptors.
    func intercepted(by chain: NebulaHTTPInterceptorChain) -> NebulaInterceptedClient {
        NebulaInterceptedClient(self, chain: chain)
    }

    /// Convenience overload: wraps this client with an interceptor chain built
    /// from `interceptors` (applied in order).
    func intercepted(by interceptors: [any NebulaHTTPInterceptor]) -> NebulaInterceptedClient {
        intercepted(by: NebulaHTTPInterceptorChain(interceptors))
    }
}
//
//  NebulaHTTPCache.swift
//  Nebula
//
//  Wave N6 — Network. The per-endpoint cache **port**: a Sendable collaborator
//  the gateway consults before a network fetch and stores into after one. Nebula
//  owns the TTL / stale-while-revalidate semantics; a concrete façade
//  (``NebulaURLCache``) holds the response bytes in the native `URLCache`. See
//  vault/03-padroes/nebula-network-endpoint-client.md.
//

import Foundation

/// A cached HTTP response paired with its freshness.
///
/// Returned by ``NebulaHTTPCache/response(for:policy:)``. A **fresh** hit
/// (`isStale == false`) is served immediately; a **stale** hit
/// (`isStale == true`, only possible under ``NebulaHTTPCachePolicy/staleWhileRevalidate(ttl:maxStale:)``
/// within its `maxStale` window) is served immediately *and* the gateway
/// revalidates in a background `Task`. This distinction lets the gateway kick a
/// background revalidate only when the entry is actually stale, not on every
/// fresh hit.
public struct NebulaCachedResponse: Sendable, Equatable {
    /// The cached response.
    public let response: NebulaHTTPResponse
    /// `true` when the entry is past its TTL but still within its
    /// `maxStale` window (stale-while-revalidate). The gateway serves it
    /// immediately and revalidates in the background.
    public let isStale: Bool

    /// Creates a cached-response snapshot.
    public init(response: NebulaHTTPResponse, isStale: Bool) {
        self.response = response
        self.isStale = isStale
    }
}

/// A per-endpoint HTTP cache: the gateway consults it before a network fetch and
/// stores successful responses into it afterwards.
///
/// Nebula owns the per-endpoint TTL / stale-while-revalidate *metadata*; a
/// concrete façade (``NebulaURLCache``) holds the response *bytes* in the native
/// `URLCache`. The gateway only consults the cache for
/// ``NebulaHTTPCachePolicy/store(ttl:)`` and
/// ``NebulaHTTPCachePolicy/staleWhileRevalidate(ttl:maxStale:)`` policies;
/// ``NebulaHTTPCachePolicy/protocolDefault`` delegates to `URLSession`'s native
/// HTTP cache and ``NebulaHTTPCachePolicy/bypass`` skips caching entirely.
///
/// `Sendable` by conformance — implementers must be safe to call from any
/// isolation. The built-in ``NebulaURLCache`` derives `Sendable` via a `Mutex`
/// (no `@unchecked`); inject a test double by conforming to this protocol.
public protocol NebulaHTTPCache: Sendable {
    /// Returns a cached response for `request` under `policy`, or `nil` when
    /// there is no usable entry (uncached, expired past its TTL + `maxStale`,
    /// or the policy is not Nebula-managed). A stale-while-revalidate hit
    /// within its `maxStale` window returns a ``NebulaCachedResponse`` with
    /// `isStale == true`.
    func response(for request: URLRequest, policy: NebulaHTTPCachePolicy) async -> NebulaCachedResponse?

    /// Stores `response` for `request` under `policy`, recording the TTL (and
    /// `maxStale`, for stale-while-revalidate) used to compute freshness.
    func store(_ response: NebulaHTTPResponse, for request: URLRequest, policy: NebulaHTTPCachePolicy) async

    /// Removes the cached entry for `request` (both Nebula's metadata and, for
    /// ``NebulaURLCache``, the native `URLCache` bytes).
    func remove(for request: URLRequest) async

    /// Removes every cached entry.
    func removeAll() async
}
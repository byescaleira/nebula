//
//  NebulaHTTPCachePolicy.swift
//  Nebula
//
//  Wave N5/N6 — Network. The per-endpoint cache policy. Introduced in N5 as a
//  pure value type (it carries no dependency on the cache port); wired into the
//  gateway in N6. Foundation-only (`Duration` is Foundation). See
//  vault/03-padroes/nebula-network-endpoint-client.md.
//

import Foundation

/// The per-endpoint cache policy.
///
/// A `Sendable` value carried by ``NebulaHTTPRequest`` (and, via the default
/// extension, by any ``NebulaHTTPEndpoint``) describing how a
/// ``NebulaHTTPClient`` should cache that endpoint's response. The Nebula
/// cache layer (``NebulaURLCache``, Wave N6) owns the TTL / stale-while-revalidate
/// semantics on top of the native `URLCache`, which holds the response bytes.
public enum NebulaHTTPCachePolicy: Sendable, Equatable, Hashable {
    /// Delegate caching to `URLSession`'s native HTTP cache
    /// (`URLRequest.CachePolicy.useProtocolCachePolicy`). No Nebula metadata.
    case protocolDefault
    /// Bypass the cache entirely (`URLRequest.CachePolicy.reloadIgnoringLocalCacheData`).
    case bypass
    /// Store the response for `ttl`; a cached response fresher than `ttl` is
    /// returned without a network call. Owned by the Nebula cache layer (N6).
    case store(ttl: Duration)
    /// Like `.store(ttl:)`, but a response staler than `ttl` and fresher than
    /// `ttl + maxStale` is returned immediately while a background revalidation
    /// refreshes the cache. Owned by the Nebula cache layer (N6).
    case staleWhileRevalidate(ttl: Duration, maxStale: Duration)
}
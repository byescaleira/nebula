//
//  NebulaHTTPEndpoint.swift
//  Nebula
//
//  Wave N5 — Network. The Endpoint port: a `Sendable` type that can build a
//  `URLRequest` (the `URLRequestConvertible` idea). Non-generic so it is
//  existential-friendly — `any NebulaHTTPEndpoint` can be passed to
//  ``NebulaHTTPClient/send(_:)`` (the Aurora work proved associatedtype-returning
//  methods can't be called on `any` existentials under Swift 6.2). Foundation-only.
//  See vault/03-padroes/nebula-network-endpoint-client.md.
//

import Foundation

/// A type that describes a single HTTP request and can build the `URLRequest`
/// for it — the `URLRequestConvertible` idea.
///
/// A `Sendable` **port** (non-generic, so `any NebulaHTTPEndpoint` is usable):
/// the app declares its endpoints as values conforming to this protocol, and a
/// ``NebulaHTTPClient`` sends them. The concrete ``NebulaHTTPRequest`` value
/// type is the ad-hoc form; apps may also conform their own enums/structs.
///
/// `cachePolicy` is a protocol **requirement** (with a default extension) so
/// that existential dispatch through the witness table honors a conformer's
/// override — a plain default-extension property would be statically dispatched
/// on `any NebulaHTTPEndpoint` and ignore the conformer's value.
public protocol NebulaHTTPEndpoint: Sendable {
    /// Builds the `URLRequest` for this endpoint, resolved against `baseURL`.
    ///
    /// A relative `path` is resolved against `baseURL`; an absolute `path` is
    /// used as-is. Query items are appended to any existing query. Throws a
    /// configuration error (surfaced to callers as a `NebulaError` kind
    /// `.unknown`) when the URL cannot be resolved.
    func urlRequest(against baseURL: URL?) throws -> URLRequest
    /// The per-endpoint cache policy. Defaults to ``NebulaHTTPCachePolicy/protocolDefault``.
    var cachePolicy: NebulaHTTPCachePolicy { get }
}

public extension NebulaHTTPEndpoint {
    /// Defaults to ``NebulaHTTPCachePolicy/protocolDefault`` — delegate caching
    /// to `URLSession`'s native HTTP cache.
    var cachePolicy: NebulaHTTPCachePolicy { .protocolDefault }
}
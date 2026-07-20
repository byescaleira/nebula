//
//  NebulaHTTPResponse.swift
//  Nebula
//
//  Wave N5 — Network. The HTTP response value returned by ``NebulaHTTPClient``
//  and produced by ``NebulaHTTPServer``'s handler. Foundation-only. See
//  vault/03-padroes/nebula-network-endpoint-client.md.
//

import Foundation

/// An HTTP response: a `Sendable` snapshot of a status code, headers, and body.
///
/// Returned by ``NebulaHTTPClient/send(_:)`` (the client port) and produced by
/// a ``NebulaHTTPServer`` handler (the server side). `Sendable` by derived
/// conformance — every stored field (`Int` / `[String: String]` / `Data`) is
/// `Sendable`, no `@unchecked`.
public struct NebulaHTTPResponse: Sendable, Equatable {
    /// The HTTP status code (e.g. `200`, `404`).
    public let statusCode: Int
    /// The response headers. Header-name case is preserved as received;
    /// duplicate headers collapse to a single value (the last).
    public let headers: [String: String]
    /// The response body.
    public let body: Data

    /// Creates a response.
    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    /// Decodes the body as `T` using `decoder`, throwing a `NebulaError`
    /// (kind `.decoding`) on failure via `NebulaJSONDecoder.decodeAsNebulaError`.
    public func decode<T: Decodable>(_ type: T.Type, using decoder: NebulaJSONDecoder = .init()) throws -> T {
        try decoder.decodeAsNebulaError(T.self, from: body).get()
    }
}
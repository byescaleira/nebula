//
//  NebulaHTTPClient.swift
//  Nebula
//
//  Wave N5 — Network. The HTTP client port: a ``NebulaGateway`` that sends
//  ``NebulaHTTPEndpoint``s and returns ``NebulaHTTPResponse``s. Non-generic so
//  `any NebulaHTTPClient` is usable (the transport requirement returns a
//  concrete response value, not an associatedtype). The verb conveniences
//  (`get`/`post`/`put`/`delete`) and the generic decode are default extensions
//  on top of the single ``send(_:)`` requirement — preserving the Wave N1 verb
//  signatures so call sites are backward-compatible. Foundation-only. See
//  vault/03-padroes/nebula-network-endpoint-client.md.
//

import Foundation

/// An HTTP client: a ``NebulaGateway`` that sends ``NebulaHTTPEndpoint``s.
///
/// The **port** for the client side of the network layer. The single
/// ``send(_:)`` requirement is the transport seam; everything else (the generic
/// decode ``send(_:as:)`` and the verb conveniences `get`/`post`/`put`/`delete`)
/// is a default extension built on top of it. The `decoder` / `encoder`
/// requirements expose the client's codec contract so the verb extensions can
/// encode bodies and decode responses with the **configured** codecs
/// (configure-once-and-freeze preserved). A test double conforms by returning
/// default codecs and a canned ``NebulaHTTPResponse`` from `send`.
public protocol NebulaHTTPClient: NebulaGateway {
    /// Sends `endpoint` and returns its response. Throws `NebulaError` (kind
    /// `.network` for transport / HTTP-status failures) on failure.
    func send(_ endpoint: NebulaHTTPEndpoint) async throws -> NebulaHTTPResponse

    /// The JSON decoder used by the decode convenience and the verbs.
    var decoder: NebulaJSONDecoder { get }
    /// The JSON encoder used by the verbs to encode request bodies.
    var encoder: NebulaJSONEncoder { get }
}

public extension NebulaHTTPClient {
    /// Sends `endpoint` and decodes the response body as `T`.
    func send<T: Decodable>(_ endpoint: NebulaHTTPEndpoint, as type: T.Type) async throws -> T {
        let response = try await send(endpoint)
        return try decoder.decodeAsNebulaError(T.self, from: response.body).get()
    }

    // MARK: - Verb conveniences (build a NebulaHTTPRequest and delegate to send)

    /// `GET path`, returning the raw response body.
    func get(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        try await send(NebulaHTTPRequest(method: .get, path: path, query: query)).body
    }

    /// `GET path`, decoding the response body as `T`.
    func get<T: Decodable>(_ type: T.Type, _ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await send(NebulaHTTPRequest(method: .get, path: path, query: query), as: T.self)
    }

    /// `POST path` with a JSON-encoded `body`, decoding the response as `T`.
    func post<T: Decodable>(_ type: T.Type, _ path: String, body: some Encodable) async throws -> T {
        let request = NebulaHTTPRequest(method: .post, path: path, body: try .json(body, using: encoder))
        return try await send(request, as: T.self)
    }

    /// `PUT path` with a JSON-encoded `body`, decoding the response as `T`.
    func put<T: Decodable>(_ type: T.Type, _ path: String, body: some Encodable) async throws -> T {
        let request = NebulaHTTPRequest(method: .put, path: path, body: try .json(body, using: encoder))
        return try await send(request, as: T.self)
    }

    /// `DELETE path`. The response body is discarded.
    func delete(_ path: String, query: [URLQueryItem] = []) async throws {
        _ = try await send(NebulaHTTPRequest(method: .delete, path: path, query: query))
    }
}
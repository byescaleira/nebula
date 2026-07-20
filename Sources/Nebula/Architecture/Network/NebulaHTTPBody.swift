//
//  NebulaHTTPBody.swift
//  Nebula
//
//  Wave N5 — Network. The HTTP request body: a `Sendable` enum carried by
//  ``NebulaHTTPRequest``. The JSON builder encodes eagerly so the value stays
//  `Sendable` (the `Encodable` is consumed, not stored). Foundation-only. See
//  vault/03-padroes/nebula-network-endpoint-client.md.
//

import Foundation

/// An HTTP request body.
///
/// A `Sendable` value (derived — `Data` and `String` are `Sendable`, no
/// `@unchecked`). The ``NebulaHTTPBody/json(_:using:)`` builder encodes an
/// `Encodable` **eagerly** into `Data` and discards the source value, so the
/// resulting body is `Sendable` even though `some Encodable` is not. (Storing
/// the `Encodable` would make the body non-`Sendable`.)
public enum NebulaHTTPBody: Sendable, Equatable {
    /// No body.
    case none
    /// A raw body with its `Content-Type` (e.g. `"application/json"`).
    case data(Data, contentType: String)

    /// Encodes `value` as JSON using `encoder` and returns `.data` with
    /// `Content-Type: application/json`. Throws a `NebulaError` (kind
    /// `.encoding`) on encode failure via `NebulaJSONEncoder.encodeAsNebulaError`.
    public static func json(_ value: some Encodable, using encoder: NebulaJSONEncoder = .init()) throws -> NebulaHTTPBody {
        let data = try encoder.encodeAsNebulaError(value).get()
        return .data(data, contentType: "application/json")
    }
}
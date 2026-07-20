//
//  NebulaHTTPMethod.swift
//  Nebula
//
//  Wave N5 — Network. The HTTP method enum used by ``NebulaHTTPRequest`` and
//  ``NebulaHTTPServer``. Foundation-only. See
//  vault/03-padroes/nebula-network-endpoint-client.md.
//

import Foundation

/// An HTTP method.
///
/// A `Sendable` value used by ``NebulaHTTPRequest`` (the client-side request
/// value) and ``NebulaHTTPServer`` (the server-side parsed request). The raw
/// value is the HTTP method string used on the wire (`"GET"`, `"POST"`, …).
public enum NebulaHTTPMethod: String, Sendable, Equatable, Hashable {
    /// `GET`.
    case get = "GET"
    /// `POST`.
    case post = "POST"
    /// `PUT`.
    case put = "PUT"
    /// `PATCH`.
    case patch = "PATCH"
    /// `DELETE`.
    case delete = "DELETE"
    /// `HEAD`.
    case head = "HEAD"
}
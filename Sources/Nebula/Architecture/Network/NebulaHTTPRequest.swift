//
//  NebulaHTTPRequest.swift
//  Nebula
//
//  Wave N5 — Network. The concrete request value type — the "Request" of the
//  Endpoint/Client/Request trio. Conforms to ``NebulaHTTPEndpoint``. Also
//  reused as the server-side parsed-request type (same shape). Foundation-only.
//  See vault/03-padroes/nebula-network-endpoint-client.md.
//

import Foundation

/// A concrete HTTP request: a `Sendable` value describing a single request's
/// method, path, query, headers, body, and cache policy.
///
/// The ad-hoc form of ``NebulaHTTPEndpoint`` — build one and pass it to
/// ``NebulaHTTPClient/send(_:)`` (or use the verb conveniences, which build one
/// for you). ``NebulaHTTPServer`` parses incoming requests into the same value
/// type. `Sendable` by derived conformance (every field is `Sendable`, no
/// `@unchecked`); `Equatable` because no closure is stored.
public struct NebulaHTTPRequest: NebulaHTTPEndpoint, Equatable {
    /// The HTTP method.
    public let method: NebulaHTTPMethod
    /// The request path — relative (resolved against the client's base URL) or
    /// absolute (used as-is).
    public let path: String
    /// Query items appended to the request URL (added to any existing query).
    public var query: [URLQueryItem]
    /// Per-request headers (override the client's default headers for the same
    /// field).
    public var headers: [String: String]
    /// The request body.
    public let body: NebulaHTTPBody
    /// The per-endpoint cache policy. Defaults to `.protocolDefault`.
    public let cachePolicy: NebulaHTTPCachePolicy

    /// Creates a request.
    public init(
        method: NebulaHTTPMethod = .get,
        path: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: NebulaHTTPBody = .none,
        cachePolicy: NebulaHTTPCachePolicy = .protocolDefault
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
        self.cachePolicy = cachePolicy
    }

    public func urlRequest(against baseURL: URL?) throws -> URLRequest {
        let url = try NebulaHTTPRequest.resolveURL(path: path, query: query, against: baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        switch body {
        case .none:
            break
        case .data(let data, let contentType):
            request.httpBody = data
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    /// Resolves the request URL. An absolute `path` (one with a scheme, e.g.
    /// `https://host/x`) is used as-is and overrides `baseURL`; otherwise a
    /// relative `path` is appended to `baseURL` (with a leading `/` stripped);
    /// otherwise a parseable but non-absolute `path` is used as-is when there is
    /// no `baseURL`. Query items are appended to any existing query. Throws a
    /// ``NebulaHTTPConfigError`` when the URL cannot be resolved.
    static func resolveURL(path: String, query: [URLQueryItem], against baseURL: URL?) throws -> URL {
        var comps: URLComponents
        if let absolute = URL(string: path), absolute.scheme != nil {
            // An absolute URL (has a scheme) overrides the base URL.
            comps = URLComponents(url: absolute, resolvingAgainstBaseURL: false) ?? URLComponents()
        } else if let baseURL {
            let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
            let resolved = baseURL.appendingPathComponent(relative)
            comps = URLComponents(url: resolved, resolvingAgainstBaseURL: false) ?? URLComponents()
        } else if let parsed = URL(string: path) {
            // No base URL; use the parseable (relative) URL as-is.
            comps = URLComponents(url: parsed, resolvingAgainstBaseURL: false) ?? URLComponents()
        } else {
            throw NebulaHTTPConfigError.noEndpointOrAbsoluteURL(path)
        }
        if !query.isEmpty {
            comps.queryItems = (comps.queryItems ?? []) + query
        }
        guard let url = comps.url else { throw NebulaHTTPConfigError.invalidURL(path) }
        return url
    }
}

/// A programmer-error (not a network failure) thrown when a request URL cannot
/// be resolved (no base URL configured and `path` is not absolute, or the
/// resulting URL is unparseable). Surfaced to callers as a `NebulaError` (kind
/// `.unknown` — a misuse, not a transport failure).
enum NebulaHTTPConfigError: Error, Sendable {
    case noEndpointOrAbsoluteURL(String)
    case invalidURL(String)
}
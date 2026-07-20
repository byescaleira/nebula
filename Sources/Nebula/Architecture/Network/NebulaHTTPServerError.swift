//
//  NebulaHTTPServerError.swift
//  Nebula
//
//  Wave N7 — Network. A server-layer error: a bind / parse / send failure
//  surfaced by ``NebulaHTTPServer``. Carries a coarse open-struct ``Kind`` (with
//  presets, mirroring ``NebulaRepositoryError``) plus a fine free-form `code`,
//  and bridges to the closed ``NebulaError/Kind`` via the caller-picked
//  ``toNebulaError(kind:)`` (no new `Kind` cases). Derives `Sendable`,
//  `Equatable`, `Hashable`. See vault/03-padroes/nebula-network-endpoint-client.md.
//

import Foundation

/// A Clean Architecture **server-layer** error: a bind / parse / send failure
/// surfaced by ``NebulaHTTPServer`` (the local HTTP/1.1 server).
///
/// `NWError` from Network.framework is **not** `Sendable`, so it is never boxed
/// across an isolation boundary — its description is folded into `message`
/// (lossy, mirroring the gateway's `URLError` bridging). `Sendable`,
/// `Equatable`, and `Hashable` are derived from the fields.
public struct NebulaHTTPServerError: NebulaFailure, Equatable, Hashable {

    /// A coarse, open-struct server error category (extensible by a string
    /// literal without a library release, mirroring ``NebulaLogCategory``).
    public struct Kind: Sendable, Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
        /// The underlying category string.
        public let rawValue: String

        /// Creates a kind from its raw string.
        public init(_ rawValue: String) { self.rawValue = rawValue }
        /// Creates a kind from a string literal.
        public init(stringLiteral value: String) { self.rawValue = value }
        /// Mirrors the raw value.
        public var description: String { rawValue }

        // MARK: - Presets (mirror NebulaRepositoryError.Kind)

        /// The listener failed to bind to its port.
        public static let bindFailed: Kind = "bind-failed"
        /// An incoming request could not be parsed as HTTP/1.1.
        public static let parseFailed: Kind = "parse-failed"
        /// The server failed to send a response.
        public static let sendFailed: Kind = "send-failed"
        /// The operation was cancelled.
        public static let cancelled: Kind = "cancelled"
        /// Anything else.
        public static let unknown: Kind = "unknown"
    }

    /// The coarse category.
    public var kind: Kind
    /// A fine free-form code (defaults to the coarse kind's raw value).
    public var code: String
    /// The human-facing message.
    public var message: String
    /// Free-form string metadata.
    public var metadata: [String: String]
    /// One nested underlying error (boxed, reusing ``NebulaError/Box``).
    public var underlying: NebulaError.Box?

    /// Creates a server error.
    public init(
        kind: Kind,
        code: String? = nil,
        message: String,
        metadata: [String: String] = [:],
        underlying: NebulaError.Box? = nil
    ) {
        self.kind = kind
        self.code = code ?? kind.rawValue
        self.message = message
        self.metadata = metadata
        self.underlying = underlying
    }

    /// The default ``NebulaError/Kind`` a server error maps to. A bind or send
    /// failure is `.network`; a parse failure is `.decoding`; cancellation and
    /// the uncategorized case are `.unknown`.
    public var coarseKind: NebulaError.Kind {
        switch kind {
        case .bindFailed, .sendFailed: return .network
        case .parseFailed:              return .decoding
        case .cancelled, .unknown:      return .unknown
        default:                        return .unknown
        }
    }

    /// Bridges to a ``NebulaError`` under `kind`. The coarse kind and code are
    /// preserved as metadata.
    public func toNebulaError(kind: NebulaError.Kind) -> NebulaError {
        var meta = metadata
        meta["NebulaCode"] = code
        return NebulaError(
            code: NebulaError.Code(domain: "Nebula.NebulaHTTPServerError", code: 0),
            kind: kind,
            message: message,
            metadata: meta,
            underlying: underlying
        )
    }

    // MARK: - Factory statics (mirror the Kind presets)

    /// A bind failure (the listener could not bind to its port).
    public static func bindFailed(_ message: String = "Bind failed", underlying: NebulaError.Box? = nil) -> NebulaHTTPServerError {
        .init(kind: .bindFailed, message: message, underlying: underlying)
    }

    /// A request-parse failure (malformed HTTP/1.1).
    public static func parseFailed(_ message: String = "Parse failed") -> NebulaHTTPServerError {
        .init(kind: .parseFailed, message: message)
    }

    /// A response-send failure.
    public static func sendFailed(_ message: String = "Send failed", underlying: NebulaError.Box? = nil) -> NebulaHTTPServerError {
        .init(kind: .sendFailed, message: message, underlying: underlying)
    }

    /// A cancellation.
    public static func cancelled(_ message: String = "Operation cancelled") -> NebulaHTTPServerError {
        .init(kind: .cancelled, message: message)
    }

    /// An uncategorized error.
    public static func unknown(_ message: String = "Unknown server error", underlying: NebulaError.Box? = nil) -> NebulaHTTPServerError {
        .init(kind: .unknown, message: message, underlying: underlying)
    }
}
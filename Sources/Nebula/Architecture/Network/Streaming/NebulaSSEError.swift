//
//  NebulaSSEError.swift
//  Nebula
//
//  Wave N17b — Streaming. A Server-Sent Events failure surfaced by
//  ``NebulaSSEEventStream``: an open-struct error mirroring
//  ``NebulaHTTPServerError`` / ``NebulaSSLPinningError`` (and
//  ``NebulaRepositoryError`` before them) — an extensible `Kind` (a string
//  literal, no library release needed to add a category) + the coarse
//  ``NebulaError/Kind`` mapping + the ``toNebulaError(kind:)`` bridge. No new
//  ``NebulaError/Kind`` case is added (the closed envelope stays closed);
//  callers that want a concrete failure declare `throws(NebulaError)` /
//  `Result<T, NebulaError>` and bridge via `toNebulaError(kind:)`.
//
//  `Sendable`, `Equatable`, and `Hashable` are derived from the fields (all
//  value types; the `@Sendable` sleeper lives in ``NebulaSSEConfiguration``,
//  not here). See vault/03-padroes/nebula-streaming.md.
//

import Foundation

/// A Server-Sent Events failure surfaced by ``NebulaSSEEventStream``.
///
/// An open-struct error mirroring ``NebulaHTTPServerError``: an extensible
/// ``Kind`` (a string literal — new categories need no library release) plus
/// the coarse ``NebulaError/Kind`` mapping and the ``toNebulaError(kind:)``
/// bridge. **No new ``NebulaError/Kind`` case** is added; callers that want a
/// concrete failure bridge via ``toNebulaError(kind:)``.
public struct NebulaSSEError: NebulaFailure, Equatable, Hashable {

    /// A coarse, open-struct SSE error category (extensible by a string
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

        // MARK: - Presets (mirror NebulaHTTPServerError.Kind)

        /// The connection / byte stream could not be opened (or exhausted the
        /// reconnect budget).
        public static let connectFailed: Kind = "connect-failed"
        /// A line could not be parsed as an SSE event field.
        public static let parseFailed: Kind = "parse-failed"
        /// Reconnect attempts were exhausted without recovery.
        public static let reconnectExhausted: Kind = "reconnect-exhausted"
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

    /// Creates an SSE error.
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

    /// The default ``NebulaError/Kind`` an SSE error maps to. A connection,
    /// parse, or reconnect-exhaustion failure is `.network`; cancellation and
    /// the uncategorized case are `.unknown`.
    public var coarseKind: NebulaError.Kind {
        switch kind {
        case .connectFailed, .parseFailed, .reconnectExhausted:
            return .network
        case .cancelled, .unknown:
            return .unknown
        default:
            return .unknown
        }
    }

    /// Bridges to a ``NebulaError`` under `kind`. The coarse kind and code are
    /// preserved as metadata.
    public func toNebulaError(kind: NebulaError.Kind) -> NebulaError {
        var meta = metadata
        meta["NebulaCode"] = code
        return NebulaError(
            code: NebulaError.Code(domain: "Nebula.NebulaSSEError", code: 0),
            kind: kind,
            message: message,
            metadata: meta,
            underlying: underlying
        )
    }

    // MARK: - Factory statics (mirror the Kind presets)

    /// A connection / byte-stream failure (optionally wrapping an underlying
    /// `URLError`).
    public static func connectFailed(_ message: String, underlying: NebulaError.Box? = nil) -> NebulaSSEError {
        .init(kind: .connectFailed, message: message, underlying: underlying)
    }

    /// A parse failure.
    public static func parseFailed(_ message: String = "SSE parse failed") -> NebulaSSEError {
        .init(kind: .parseFailed, message: message)
    }

    /// Reconnect attempts exhausted.
    public static func reconnectExhausted(_ message: String = "SSE reconnect attempts exhausted") -> NebulaSSEError {
        .init(kind: .reconnectExhausted, message: message)
    }

    /// A cancellation.
    public static func cancelled(_ message: String = "SSE stream cancelled") -> NebulaSSEError {
        .init(kind: .cancelled, message: message)
    }

    /// An uncategorized error.
    public static func unknown(_ message: String = "Unknown SSE error", underlying: NebulaError.Box? = nil) -> NebulaSSEError {
        .init(kind: .unknown, message: message, underlying: underlying)
    }
}
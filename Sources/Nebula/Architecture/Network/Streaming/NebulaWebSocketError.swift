//
//  NebulaWebSocketError.swift
//  Nebula
//
//  Wave N17b — Streaming. A WebSocket failure surfaced by
//  ``NebulaURLSessionWebSocket`` (and surfaced to consumers of the
//  ``NebulaWebSocketClient`` port): an open-struct error mirroring
//  ``NebulaHTTPServerError`` / ``NebulaSSLPinningError`` / ``NebulaSSEError`` —
//  an extensible `Kind` (a string literal, no library release needed to add a
//  category) + the coarse ``NebulaError/Kind`` mapping + the
//  ``toNebulaError(kind:)`` bridge. No new ``NebulaError/Kind`` case is added
//  (the closed envelope stays closed); callers that want a concrete failure
//  declare `throws(NebulaError)` / `Result<T, NebulaError>` and bridge via
//  `toNebulaError(kind:)`.
//
//  `Sendable`, `Equatable`, and `Hashable` are derived from the fields (all
//  value types). See vault/03-padroes/nebula-streaming.md.
//

import Foundation

/// A WebSocket failure surfaced by ``NebulaURLSessionWebSocket``.
///
/// An open-struct error mirroring ``NebulaHTTPServerError``: an extensible
/// ``Kind`` (a string literal — new categories need no library release) plus
/// the coarse ``NebulaError/Kind`` mapping and the ``toNebulaError(kind:)``
/// bridge. **No new ``NebulaError/Kind`` case** is added; callers that want a
/// concrete failure bridge via ``toNebulaError(kind:)``.
public struct NebulaWebSocketError: NebulaFailure, Equatable, Hashable {

    /// A coarse, open-struct WebSocket error category (extensible by a string
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

        /// The WebSocket connection could not be opened.
        public static let connectFailed: Kind = "connect-failed"
        /// A `send` failed.
        public static let sendFailed: Kind = "send-failed"
        /// A `receive` failed.
        public static let receiveFailed: Kind = "receive-failed"
        /// A ping failed.
        public static let pingFailed: Kind = "ping-failed"
        /// The peer closed the socket (carries the close code + reason).
        public static let closed: Kind = "closed"
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

    /// Creates a WebSocket error.
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

    /// The default ``NebulaError/Kind`` a WebSocket error maps to. A connect,
    /// send, receive, ping, or peer-close failure is `.network`; cancellation
    /// and the uncategorized case are `.unknown`.
    public var coarseKind: NebulaError.Kind {
        switch kind {
        case .connectFailed, .sendFailed, .receiveFailed, .pingFailed, .closed:
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
            code: NebulaError.Code(domain: "Nebula.NebulaWebSocketError", code: 0),
            kind: kind,
            message: message,
            metadata: meta,
            underlying: underlying
        )
    }

    // MARK: - Factory statics (mirror the Kind presets)

    /// A connection failure (optionally wrapping an underlying `URLError`).
    public static func connectFailed(_ message: String, underlying: NebulaError.Box? = nil) -> NebulaWebSocketError {
        .init(kind: .connectFailed, message: message, underlying: underlying)
    }

    /// A send failure.
    public static func sendFailed(_ message: String, underlying: NebulaError.Box? = nil) -> NebulaWebSocketError {
        .init(kind: .sendFailed, message: message, underlying: underlying)
    }

    /// A receive failure.
    public static func receiveFailed(_ message: String, underlying: NebulaError.Box? = nil) -> NebulaWebSocketError {
        .init(kind: .receiveFailed, message: message, underlying: underlying)
    }

    /// A ping failure.
    public static func pingFailed(_ message: String = "WebSocket ping failed", underlying: NebulaError.Box? = nil) -> NebulaWebSocketError {
        .init(kind: .pingFailed, message: message, underlying: underlying)
    }

    /// A peer-close event (carries the close code in metadata, reason in the
    /// message).
    public static func closed(
        code: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) -> NebulaWebSocketError {
        var meta: [String: String] = ["WebSocketCloseCode": "\(code.rawValue)"]
        if let reason, let reasonString = String(data: reason, encoding: .utf8) {
            meta["WebSocketCloseReason"] = reasonString
        }
        return .init(kind: .closed, message: "WebSocket closed: code \(code.rawValue)", metadata: meta)
    }

    /// A cancellation.
    public static func cancelled(_ message: String = "WebSocket cancelled") -> NebulaWebSocketError {
        .init(kind: .cancelled, message: message)
    }

    /// An uncategorized error.
    public static func unknown(_ message: String = "Unknown WebSocket error", underlying: NebulaError.Box? = nil) -> NebulaWebSocketError {
        .init(kind: .unknown, message: message, underlying: underlying)
    }
}
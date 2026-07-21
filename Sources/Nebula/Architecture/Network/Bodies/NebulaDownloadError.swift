//
//  NebulaDownloadError.swift
//  Nebula
//
//  Wave N17c — Bodies & downloads. A download failure surfaced by
//  ``NebulaDownload``: an open-struct error mirroring ``NebulaSSEError`` /
//  ``NebulaHTTPServerError`` — an extensible `Kind` (a string literal, no
//  library release needed to add a category) + the coarse
//  ``NebulaError/Kind`` mapping + the ``toNebulaError(kind:)`` bridge. No new
//  ``NebulaError/Kind`` case is added (the closed envelope stays closed);
//  callers that want a concrete failure declare `throws(NebulaError)` /
//  `Result<T, NebulaError>` and bridge via `toNebulaError(kind:)`.
//
//  `Sendable`, `Equatable`, and `Hashable` are derived from the fields (all
//  value types; no `@Sendable` closure lives here). See
//  vault/03-padroes/nebula-bodies-downloads.md.
//

import Foundation

/// A download failure surfaced by ``NebulaDownload``.
///
/// An open-struct error mirroring ``NebulaHTTPServerError`` / ``NebulaSSEError``:
/// an extensible ``Kind`` (a string literal — new categories need no library
/// release) plus the coarse ``NebulaError/Kind`` mapping and the
/// ``toNebulaError(kind:)`` bridge. **No new ``NebulaError/Kind`` case** is
/// added; callers that want a concrete failure bridge via ``toNebulaError(kind:)``.
public struct NebulaDownloadError: NebulaFailure, Equatable, Hashable {

    /// A coarse, open-struct download error category (extensible by a string
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

        // MARK: - Presets (mirror NebulaSSEError.Kind)

        /// The download itself failed (transport or server error).
        public static let downloadFailed: Kind = "download-failed"
        /// The temp-file → destination move failed.
        public static let moveFailed: Kind = "move-failed"
        /// A resume-data retry failed.
        public static let resumeFailed: Kind = "resume-failed"
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

    /// Creates a download error.
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

    /// The default ``NebulaError/Kind`` a download error maps to. A download,
    /// move, or resume failure is `.network`; cancellation and the
    /// uncategorized case are `.unknown`.
    public var coarseKind: NebulaError.Kind {
        switch kind {
        case .downloadFailed, .moveFailed, .resumeFailed:
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
            code: NebulaError.Code(domain: "Nebula.NebulaDownloadError", code: 0),
            kind: kind,
            message: message,
            metadata: meta,
            underlying: underlying
        )
    }

    // MARK: - Factory statics (mirror the Kind presets)

    /// A download failure (optionally wrapping an underlying `URLError`).
    public static func downloadFailed(_ message: String, underlying: NebulaError.Box? = nil) -> NebulaDownloadError {
        .init(kind: .downloadFailed, message: message, underlying: underlying)
    }

    /// A temp-file → destination move failure.
    public static func moveFailed(_ message: String, underlying: NebulaError.Box? = nil) -> NebulaDownloadError {
        .init(kind: .moveFailed, message: message, underlying: underlying)
    }

    /// A resume-data retry failure.
    public static func resumeFailed(_ message: String, underlying: NebulaError.Box? = nil) -> NebulaDownloadError {
        .init(kind: .resumeFailed, message: message, underlying: underlying)
    }

    /// A cancellation.
    public static func cancelled(_ message: String = "Download cancelled") -> NebulaDownloadError {
        .init(kind: .cancelled, message: message)
    }

    /// An uncategorized error.
    public static func unknown(_ message: String = "Unknown download error", underlying: NebulaError.Box? = nil) -> NebulaDownloadError {
        .init(kind: .unknown, message: message, underlying: underlying)
    }
}
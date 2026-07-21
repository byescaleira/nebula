//
//  NebulaSSLPinningError.swift
//  Nebula
//
//  Wave N17a — Network hardening. The SSL/TLS pinning evaluation failure: an
//  open-struct error mirroring ``NebulaHTTPServerError`` (and
//  ``NebulaRepositoryError`` before it) — an extensible `Kind` (a string
//  literal, no library release needed to add a category) + the coarse
//  ``NebulaError/Kind`` mapping + the ``toNebulaError(kind:)`` bridge. No new
//  ``NebulaError/Kind`` case is added (the closed envelope stays closed);
//  callers that want a concrete failure declare `throws(NebulaError)` /
//  `Result<T, NebulaError>` and bridge via `toNebulaError(kind:)`.
//
//  The live gateway path does NOT surface this error: a pinning failure in
//  ``NebulaURLSessionDelegate`` calls the completion with
//  `.cancelAuthenticationChallenge`, and `URLSession` then surfaces a
//  `URLError` to ``NebulaHTTPGateway``, which already bridges
//  `URLError → NebulaError(urlError:)` — no gateway change, no new bridge
//  wired. This error exists for non-URLSession consumers of
//  ``NebulaSSLPinningEvaluator`` (and for the delegate's optional
//  ``NebulaLogger`` diagnostics). See vault/03-padroes/nebula-ssl-pinning.md.
//

import Foundation

/// An SSL/TLS pinning evaluation failure.
///
/// An open-struct error mirroring ``NebulaHTTPServerError``: an extensible
/// ``Kind`` (a string literal — new categories need no library release) plus
/// the coarse ``NebulaError/Kind`` mapping and the ``toNebulaError(kind:)``
/// bridge. **No new ``NebulaError/Kind`` case** is added; callers that want a
/// concrete failure bridge via ``toNebulaError(kind:)``.
public struct NebulaSSLPinningError: NebulaFailure, Equatable, Hashable {

    /// A coarse, open-struct pinning error category (extensible by a string
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

        /// The chain validated but no cert's SPKI digest matched a pin.
        public static let noMatchingPin: Kind = "no-matching-pin"
        /// No pin set applies to the host.
        public static let noPinForHost: Kind = "no-pin-for-host"
        /// The OS trust store rejected the chain.
        public static let chainValidationFailed: Kind = "chain-validation-failed"
        /// A public key or its DER could not be extracted.
        public static let spkiExtractionFailed: Kind = "spki-extraction-failed"
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

    /// Creates a pinning error.
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

    /// The default ``NebulaError/Kind`` a pinning error maps to. A pin mismatch
    /// or chain/SPKI failure is `.network`; cancellation and the uncategorized
    /// case are `.unknown`.
    public var coarseKind: NebulaError.Kind {
        switch kind {
        case .noMatchingPin, .noPinForHost, .chainValidationFailed, .spkiExtractionFailed:
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
            code: NebulaError.Code(domain: "Nebula.NebulaSSLPinningError", code: 0),
            kind: kind,
            message: message,
            metadata: meta,
            underlying: underlying
        )
    }

    // MARK: - Factory statics (mirror the Kind presets)

    /// A no-matching-pin failure.
    public static func noMatchingPin(_ message: String = "No matching SPKI pin") -> NebulaSSLPinningError {
        .init(kind: .noMatchingPin, message: message)
    }

    /// A no-pin-for-host failure.
    public static func noPinForHost(_ message: String = "No pin configured for host") -> NebulaSSLPinningError {
        .init(kind: .noPinForHost, message: message)
    }

    /// A chain-validation failure (the OS trust store rejected the chain).
    public static func chainValidationFailed(_ message: String, underlying: NebulaError.Box? = nil) -> NebulaSSLPinningError {
        .init(kind: .chainValidationFailed, message: message, underlying: underlying)
    }

    /// An SPKI-extraction failure.
    public static func spkiExtractionFailed(_ message: String = "SPKI extraction failed") -> NebulaSSLPinningError {
        .init(kind: .spkiExtractionFailed, message: message)
    }

    /// A cancellation.
    public static func cancelled(_ message: String = "Pinning cancelled") -> NebulaSSLPinningError {
        .init(kind: .cancelled, message: message)
    }

    /// An uncategorized error.
    public static func unknown(_ message: String = "Unknown pinning error", underlying: NebulaError.Box? = nil) -> NebulaSSLPinningError {
        .init(kind: .unknown, message: message, underlying: underlying)
    }
}
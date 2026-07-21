//
//  NebulaNotificationsError.swift
//  Nebula
//
//  Wave N15a — App-readiness. A notification-layer error: a `UNUserNotificationCenter`
// failure surfaced by ``NebulaUNNotificationCenter`` (not-authorized, a
// scheduling failure, an invalid trigger, a cancellation). Carries a coarse
// open-struct ``Kind`` (with presets, mirroring ``NebulaKeychainError`` /
// ``NebulaRepositoryError``) plus a fine free-form `code`, and bridges to the
// closed ``NebulaError/Kind`` via the caller-picked ``toNebulaError(kind:)``
// (no new `Kind` cases — `UNError`/`NSError` map to `.cocoa`, the CoreFoundation
// bucket; not-authorized / invalid-trigger / cancelled / unknown map to
// `.unknown`, the layer-`Kind` distinction lives here). Derives `Sendable`,
// `Equatable`, `Hashable`. See vault/03-padroes/nebula-notifications.md.
//

import Foundation

/// A Clean Architecture **notification-layer** error: a `UNUserNotificationCenter`
/// failure surfaced by ``NebulaUNNotificationCenter``.
///
/// `Sendable`, `Equatable`, and `Hashable` are derived from the fields, so a test
/// can assert a specific notification error:
///
/// ```swift
/// #expect(throws: NebulaNotificationsError.notAuthorized()) {
///     try await center.add(request)
/// }
/// ```
public struct NebulaNotificationsError: NebulaFailure, Equatable, Hashable {

    /// A coarse, open-struct notification error category (extensible by a string
    /// literal without a library release, mirroring ``NebulaKeychainError/Kind``).
    public struct Kind: Sendable, Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
        /// The underlying category string.
        public let rawValue: String

        /// Creates a kind from its raw string.
        public init(_ rawValue: String) { self.rawValue = rawValue }
        /// Creates a kind from a string literal.
        public init(stringLiteral value: String) { self.rawValue = value }
        /// Mirrors the raw value.
        public var description: String { rawValue }

        // MARK: - Presets (mirror NebulaKeychainError.Kind)

        /// Authorization was not granted (or not requested) for the requested
        /// notification type.
        public static let notAuthorized: Kind = "not-authorized"
        /// Scheduling a request failed (the SDK rejected it).
        public static let schedulingFailed: Kind = "scheduling-failed"
        /// The trigger was invalid (e.g. a non-positive time interval).
        public static let invalidTrigger: Kind = "invalid-trigger"
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

    /// Creates a notification error.
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

    /// The default ``NebulaError/Kind`` a notification error maps to. SDK
    /// failures (`UNError` / `NSError` surfaced as `schedulingFailed`) map to
    /// `.cocoa` (the `CocoaError` / `NSError` bucket, per
    /// ``NebulaError/Kind/cocoa``); `notAuthorized` / `invalidTrigger` /
    /// `cancelled` / `unknown` map to `.unknown` (the layer-`Kind` distinction
    /// lives in this layer's ``Kind``, like ``NebulaRepositoryError/Kind/notFound``).
    public var coarseKind: NebulaError.Kind {
        switch kind {
        case .schedulingFailed:
            return .cocoa
        case .notAuthorized, .invalidTrigger, .cancelled, .unknown:
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
            code: NebulaError.Code(domain: "Nebula.NebulaNotificationsError", code: 0),
            kind: kind,
            message: message,
            metadata: meta,
            underlying: underlying
        )
    }

    // MARK: - Factory statics (mirror the Kind presets)

    /// A not-authorized error.
    public static func notAuthorized(_ message: String = "Notification authorization not granted") -> NebulaNotificationsError {
        .init(kind: .notAuthorized, message: message)
    }

    /// A scheduling-failed error (optionally boxing an underlying SDK error).
    public static func schedulingFailed(_ message: String = "Scheduling the notification failed", underlying: NebulaError.Box? = nil) -> NebulaNotificationsError {
        .init(kind: .schedulingFailed, message: message, underlying: underlying)
    }

    /// An invalid-trigger error.
    public static func invalidTrigger(_ message: String = "Invalid notification trigger") -> NebulaNotificationsError {
        .init(kind: .invalidTrigger, message: message)
    }

    /// A cancellation.
    public static func cancelled(_ message: String = "Notification operation cancelled") -> NebulaNotificationsError {
        .init(kind: .cancelled, message: message)
    }

    /// An uncategorized error.
    public static func unknown(_ message: String = "Unknown notification error", underlying: NebulaError.Box? = nil) -> NebulaNotificationsError {
        .init(kind: .unknown, message: message, underlying: underlying)
    }
}
//
//  NebulaBackgroundTaskError.swift
//  Nebula
//
//  Wave N15b — App-readiness. A background-task-layer error: a `BGTaskScheduler`
//  failure surfaced by ``NebulaBGTaskScheduler`` (not-permitted, a scheduling
//  failure, too many pending, unavailable, immediate-run-ineligible). Carries a
//  coarse open-struct ``Kind`` (with presets, mirroring
//  ``NebulaKeychainError`` / ``NebulaNotificationsError``) plus a fine free-form
//  `code`, and bridges to the closed ``NebulaError/Kind`` via the caller-picked
//  ``toNebulaError(kind:)`` (no new `Kind` cases — `BGTaskScheduler.Error` /
//  `NSError` map to `.cocoa`, the `NSError` bucket; not-permitted /
//  too-many-pending / unavailable / immediate-run-ineligible / unknown map to
//  `.unknown`, the layer-`Kind` distinction lives here). Derives `Sendable`,
//  `Equatable`, `Hashable`. See vault/03-padroes/nebula-background-tasks.md.
//

import Foundation

/// A Clean Architecture **background-task-layer** error: a `BGTaskScheduler`
/// failure surfaced by ``NebulaBGTaskScheduler``.
///
/// `Sendable`, `Equatable`, and `Hashable` are derived from the fields, so a
/// test can assert a specific background-task error:
///
/// ```swift
/// #expect(throws: NebulaBackgroundTaskError.notPermitted()) {
///     try await scheduler.submit(request)
/// }
/// ```
public struct NebulaBackgroundTaskError: NebulaFailure, Equatable, Hashable {

    /// A coarse, open-struct background-task error category (extensible by a
    /// string literal without a library release, mirroring
    /// ``NebulaKeychainError/Kind``). Presets mirror
    /// `BGTaskSchedulerErrorCode`.
    public struct Kind: Sendable, Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
        /// The underlying category string.
        public let rawValue: String

        /// Creates a kind from its raw string.
        public init(_ rawValue: String) { self.rawValue = rawValue }
        /// Creates a kind from a string literal.
        public init(stringLiteral value: String) { self.rawValue = value }
        /// Mirrors the raw value.
        public var description: String { rawValue }

        // MARK: - Presets (mirror BGTaskSchedulerErrorCode)

        /// The identifier isn't in the app's permitted-identifiers list, or the
        /// app lacks the background mode / denied background launches
        /// (`BGTaskSchedulerErrorCodeNotPermitted`).
        public static let notPermitted: Kind = "not-permitted"
        /// Scheduling a request failed (the SDK rejected it).
        public static let schedulingFailed: Kind = "scheduling-failed"
        /// Too many pending requests of this type (1 refresh / 10 processing max;
        /// `BGTaskSchedulerErrorCodeTooManyPendingTaskRequests`).
        public static let tooManyPending: Kind = "too-many-pending"
        /// Background scheduling is unavailable (background refresh disabled or
        /// the app isn't permitted — `BGTaskSchedulerErrorCodeUnavailable`).
        public static let unavailable: Kind = "unavailable"
        /// A continued-processing request was not allowed to immediately run due
        /// to system conditions (deferred to N15c; preset kept for forward-compat).
        public static let immediateRunIneligible: Kind = "immediate-run-ineligible"
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

    /// Creates a background-task error.
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

    /// The default ``NebulaError/Kind`` a background-task error maps to. SDK
    /// failures (`BGTaskScheduler.Error` / `NSError` surfaced as
    /// `schedulingFailed`) map to `.cocoa` (the `CocoaError` / `NSError` bucket,
    /// per ``NebulaError/Kind/cocoa``); `notPermitted` / `tooManyPending` /
    /// `unavailable` / `immediateRunIneligible` / `unknown` map to `.unknown`
    /// (the layer-`Kind` distinction lives in this layer's ``Kind``, like
    /// ``NebulaRepositoryError/Kind/notFound``).
    public var coarseKind: NebulaError.Kind {
        switch kind {
        case .schedulingFailed:
            return .cocoa
        case .notPermitted, .tooManyPending, .unavailable, .immediateRunIneligible, .unknown:
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
            code: NebulaError.Code(domain: "Nebula.NebulaBackgroundTaskError", code: 0),
            kind: kind,
            message: message,
            metadata: meta,
            underlying: underlying
        )
    }

    // MARK: - Factory statics (mirror the Kind presets)

    /// A not-permitted error (optionally boxing an underlying SDK error).
    public static func notPermitted(_ message: String = "Background task not permitted", underlying: NebulaError.Box? = nil) -> NebulaBackgroundTaskError {
        .init(kind: .notPermitted, message: message, underlying: underlying)
    }

    /// A scheduling-failed error (optionally boxing an underlying SDK error).
    public static func schedulingFailed(_ message: String = "Scheduling the background task failed", underlying: NebulaError.Box? = nil) -> NebulaBackgroundTaskError {
        .init(kind: .schedulingFailed, message: message, underlying: underlying)
    }

    /// A too-many-pending error (optionally boxing an underlying SDK error).
    public static func tooManyPending(_ message: String = "Too many pending background task requests", underlying: NebulaError.Box? = nil) -> NebulaBackgroundTaskError {
        .init(kind: .tooManyPending, message: message, underlying: underlying)
    }

    /// An unavailable error (optionally boxing an underlying SDK error).
    public static func unavailable(_ message: String = "Background scheduling unavailable", underlying: NebulaError.Box? = nil) -> NebulaBackgroundTaskError {
        .init(kind: .unavailable, message: message, underlying: underlying)
    }

    /// An immediate-run-ineligible error (optionally boxing an underlying SDK error).
    public static func immediateRunIneligible(_ message: String = "Immediate run not eligible", underlying: NebulaError.Box? = nil) -> NebulaBackgroundTaskError {
        .init(kind: .immediateRunIneligible, message: message, underlying: underlying)
    }

    /// An uncategorized error.
    public static func unknown(_ message: String = "Unknown background task error", underlying: NebulaError.Box? = nil) -> NebulaBackgroundTaskError {
        .init(kind: .unknown, message: message, underlying: underlying)
    }
}
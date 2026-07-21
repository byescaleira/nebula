//
//  NebulaKeychainError.swift
//  Nebula
//
//  Wave N9 — App-readiness. A Keychain-layer error: a `SecItem*` failure
// surfaced by ``NebulaKeychain``. Carries a coarse open-struct ``Kind`` (with
// presets, mirroring ``NebulaRepositoryError``/``NebulaHTTPServerError``) plus a
// fine free-form `code`, the raw `OSStatus` from the Security C API, and bridges
// to the closed ``NebulaError/Kind`` via the caller-picked ``toNebulaError(kind:)``
// (no new `Kind` cases — `errSec*` codes map to `.cocoa`, the CoreFoundation /
// OSStatus bucket). `OSStatus` is `Int32` (trivially `Sendable`), stored on the
// struct, not boxed (the `NWError`-folded-into-message idiom; `underlying` is
// reserved for a nested `NebulaError`). Derives `Sendable`, `Equatable`,
// `Hashable`. See vault/03-padroes/nebula-keychain.md.
//

import Foundation
import Security

/// A Clean Architecture **Keychain-layer** error: a `SecItem*` failure surfaced
/// by ``NebulaKeychain`` (the Security.framework façade).
///
/// The raw `OSStatus` from the C API is stored (not boxed) — it is `Int32`,
/// trivially `Sendable`. `Sendable`, `Equatable`, and `Hashable` are derived from
/// the fields, so a test can assert a specific Keychain error:
///
/// ```swift
/// #expect(throws: NebulaKeychainError.duplicateItem()) {
///     try keychain.setData(Data("v".utf8), forKey: "k")
/// }
/// ```
public struct NebulaKeychainError: NebulaFailure, Equatable, Hashable {

    /// A coarse, open-struct Keychain error category (extensible by a string
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

        // MARK: - Presets (mirror NebulaRepositoryError.Kind / NebulaHTTPServerError.Kind)

        /// The item was not found (`errSecItemNotFound`). Distinct from a genuine
        /// failure — `data(forKey:)` returns `nil` for this, it does not throw.
        public static let itemNotFound: Kind = "item-not-found"
        /// The item already exists (`errSecDuplicateItem`).
        public static let duplicateItem: Kind = "duplicate-item"
        /// Authentication failed (`errSecAuthFailed`).
        public static let authFailed: Kind = "auth-failed"
        /// The device is locked and the item cannot be accessed
        /// (`errSecInteractionNotAllowed`). Non-destructive — never delete on this.
        public static let interactionNotAllowed: Kind = "interaction-not-allowed"
        /// The app lacks the entitlement for the requested access group
        /// (`errSecMissingEntitlement`).
        public static let missingEntitlement: Kind = "missing-entitlement"
        /// The operation was cancelled (`errSecUserCanceled` / `errSecCanceled`).
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
    /// The raw `OSStatus` from the Security C API (`Int32`, trivially `Sendable`).
    public var status: OSStatus
    /// Free-form string metadata.
    public var metadata: [String: String]
    /// One nested underlying error (boxed, reusing ``NebulaError/Box``).
    public var underlying: NebulaError.Box?

    /// Creates a Keychain error.
    public init(
        kind: Kind,
        code: String? = nil,
        message: String,
        status: OSStatus = 0,
        metadata: [String: String] = [:],
        underlying: NebulaError.Box? = nil
    ) {
        self.kind = kind
        self.code = code ?? kind.rawValue
        self.message = message
        self.status = status
        self.metadata = metadata
        self.underlying = underlying
    }

    /// The default ``NebulaError/Kind`` a Keychain error maps to. The CoreFoundation
    /// / OSStatus failures (`duplicateItem` / `authFailed` / `interactionNotAllowed`
    /// / `missingEntitlement`) map to `.cocoa` (the `CocoaError` / OSStatus bucket,
    /// per ``NebulaError/Kind/cocoa``); `itemNotFound` / `cancelled` / `unknown`
    /// map to `.unknown` (the not-found distinction lives in this layer's ``Kind``,
    /// like ``NebulaRepositoryError/Kind/notFound``).
    public var coarseKind: NebulaError.Kind {
        switch kind {
        case .duplicateItem, .authFailed, .interactionNotAllowed, .missingEntitlement:
            return .cocoa
        case .itemNotFound, .cancelled, .unknown:
            return .unknown
        default:
            return .unknown
        }
    }

    /// Bridges to a ``NebulaError`` under `kind`. The coarse kind, code, and raw
    /// `OSStatus` are preserved as metadata.
    public func toNebulaError(kind: NebulaError.Kind) -> NebulaError {
        var meta = metadata
        meta["NebulaCode"] = code
        meta["NebulaOSStatus"] = String(status)
        return NebulaError(
            code: NebulaError.Code(domain: "Nebula.NebulaKeychainError", code: Int(status)),
            kind: kind,
            message: message,
            metadata: meta,
            underlying: underlying
        )
    }

    // MARK: - Factory statics (mirror the Kind presets)

    /// An item-not-found error (`errSecItemNotFound`).
    public static func itemNotFound(_ message: String = "Keychain item not found", status: OSStatus = errSecItemNotFound) -> NebulaKeychainError {
        .init(kind: .itemNotFound, message: message, status: status)
    }

    /// A duplicate-item error (`errSecDuplicateItem`).
    public static func duplicateItem(_ message: String = "Keychain item already exists", status: OSStatus = errSecDuplicateItem) -> NebulaKeychainError {
        .init(kind: .duplicateItem, message: message, status: status)
    }

    /// An authentication-failed error (`errSecAuthFailed`).
    public static func authFailed(_ message: String = "Keychain authentication failed", status: OSStatus = errSecAuthFailed) -> NebulaKeychainError {
        .init(kind: .authFailed, message: message, status: status)
    }

    /// An interaction-not-allowed error (`errSecInteractionNotAllowed`). The device
    /// is locked — non-destructive; never delete on this error.
    public static func interactionNotAllowed(_ message: String = "Keychain interaction not allowed (device locked)", status: OSStatus = errSecInteractionNotAllowed) -> NebulaKeychainError {
        .init(kind: .interactionNotAllowed, message: message, status: status)
    }

    /// A missing-entitlement error (`errSecMissingEntitlement`).
    public static func missingEntitlement(_ message: String = "Keychain access group entitlement missing", status: OSStatus = errSecMissingEntitlement) -> NebulaKeychainError {
        .init(kind: .missingEntitlement, message: message, status: status)
    }

    /// A cancellation (`errSecUserCanceled` / `errSecCanceled`).
    public static func cancelled(_ message: String = "Keychain operation cancelled", status: OSStatus = errSecUserCanceled) -> NebulaKeychainError {
        .init(kind: .cancelled, message: message, status: status)
    }

    /// An uncategorized error.
    public static func unknown(_ message: String = "Unknown keychain error", status: OSStatus = 0, underlying: NebulaError.Box? = nil) -> NebulaKeychainError {
        .init(kind: .unknown, message: message, status: status, underlying: underlying)
    }
}
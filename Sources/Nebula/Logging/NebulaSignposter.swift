//
//  NebulaSignposter.swift
//  Nebula
//
//  Sendable wrappers around `os.OSSignposter` / `OSSignpostID` /
//  `OSSignpostIntervalState` for Instruments-integrated measurement.
//
//  IMPORTANT — like `os.Logger`, `os.OSSignposter` CANNOT be wrapped: its
//  `emitEvent`/`beginInterval`/`endInterval`/`withIntervalSignpost` methods
//  carry `@_semantics("constant_evaluable")`, which requires the `name`
//  (`StaticString`) and message (`SignpostMetadata = OSLogMessage`) to be
//  literals at the `OSSignposter` call site. Forwarding a parameter fails
//  ("globalStringTablePointer builtin must be used only on string literals").
//  NebulaSignposter therefore exposes the underlying `os.OSSignposter`
//  (``osSignposter``) for those operations, and provides Nebula-typed
//  `makeSignpostID` and the ID/state wrappers. See
//  vault/01-fundamentos/nebula-logging.md (Corrections).
//

import Foundation
import os

/// A `Sendable` alias for `os.SignpostMetadata` (`= os.OSLogMessage`), the
/// compile-time-literal signpost metadata type.
public typealias NebulaSignpostMetadata = os.SignpostMetadata

/// A `Sendable` wrapper around `os.OSSignpostID` — the identity token that
/// ties an interval's `begin`/`end` together in Instruments.
public struct NebulaSignpostID: Sendable, Hashable, Comparable {
    /// The underlying `os.OSSignpostID`.
    public let rawValue: os.OSSignpostID

    /// Creates a wrapper from an `os.OSSignpostID`.
    public init(_ rawValue: os.OSSignpostID) {
        self.rawValue = rawValue
    }

    /// The default exclusive id (a fresh, non-shared id).
    public static let exclusive: NebulaSignpostID = .init(.exclusive)
    /// An id that never matches a real interval.
    public static let invalid: NebulaSignpostID = .init(.invalid)
    /// The null id.
    public static let null: NebulaSignpostID = .init(.null)

    public static func < (lhs: NebulaSignpostID, rhs: NebulaSignpostID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public static func == (lhs: NebulaSignpostID, rhs: NebulaSignpostID) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    public func hash(into hasher: inout Hasher) {
        // `os.OSSignpostID` is Comparable/Equatable but NOT Hashable; hash the
        // underlying `os_signpost_id_t` scalar (`OSSignpostID.rawValue`) instead.
        hasher.combine(rawValue.rawValue)
    }
}

/// A `Sendable` wrapper around `os.OSSignpostIntervalState` — the opaque
/// token returned by `OSSignposter.beginInterval` and consumed by
/// `OSSignposter.endInterval`.
public struct NebulaSignpostIntervalState: Sendable, Hashable {
    /// The underlying `os.OSSignpostIntervalState` (`@unchecked Sendable` class;
    /// immutable after construction, so the wrapper is soundly `Sendable`).
    public let rawValue: os.OSSignpostIntervalState

    /// Creates a wrapper from an `os.OSSignpostIntervalState`.
    public init(_ rawValue: os.OSSignpostIntervalState) {
        self.rawValue = rawValue
    }

    // Note: `OSSignpostIntervalState.signpostID` is `internal` in the os overlay,
    // so this wrapper cannot re-expose it; compare/hash by object identity.

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(rawValue))
    }

    public static func == (lhs: NebulaSignpostIntervalState, rhs: NebulaSignpostIntervalState) -> Bool {
        lhs.rawValue === rhs.rawValue
    }
}

/// A `Sendable` facade over `os.OSSignposter` for Instruments-integrated
/// measurement (WWDC18 405).
///
/// Because `os.OSSignposter` cannot be wrapped (its signpost methods require
/// literal `name`/message at the call site), this type exposes the underlying
/// ``osSignposter`` for `emitEvent`/`beginInterval`/`endInterval`/
/// `withIntervalSignpost`, and provides Nebula-typed
/// ``makeSignpostID()``/``makeSignpostID(from:)`` plus the ID/state wrappers:
///
/// ```swift
/// let s = NebulaSignposter(subsystem: "com.acme.app")
/// let id = s.makeSignpostID()
/// let state = s.osSignposter.beginInterval("load", id: id.rawValue)
/// // ... work ...
/// s.osSignposter.endInterval("load", state)
/// ```
///
/// Like ``NebulaLogger``, this is a value type with `let` storage holding an
/// `os.OSSignposter` (itself `@unchecked Sendable`), so `Sendable` is soundly
/// derived without authoring `@unchecked` on Nebula's own type.
public struct NebulaSignposter: Sendable {
    /// The underlying `os.OSSignposter`. Use this for `emitEvent`/
    /// `beginInterval`/`endInterval`/`withIntervalSignpost` with literal names.
    @usableFromInline
    let signposter: os.OSSignposter

    /// The subsystem this signposter reports under.
    public let subsystem: String
    /// The category this signposter reports under.
    public let category: NebulaLogCategory

    /// Creates a signposter for the given `subsystem` and `category`.
    public init(subsystem: String, category: NebulaLogCategory = .measure) {
        self.subsystem = subsystem
        self.category = category
        self.signposter = os.OSSignposter(subsystem: subsystem, category: category.rawValue)
    }

    /// Creates a signposter sharing a logger's `os.OSLog` (via
    /// `OSSignposter(logger:)`), recording the `subsystem`/`category` Nebula
    /// already knows (the underlying `os.Logger` does not expose them).
    public init(logger: os.Logger, subsystem: String, category: NebulaLogCategory = .measure) {
        self.signposter = os.OSSignposter(logger: logger)
        self.subsystem = subsystem
        self.category = category
    }

    /// Creates a signposter wrapping an existing `os.OSSignposter`.
    public init(_ rawValue: os.OSSignposter, subsystem: String = "com.nebula.foundation", category: NebulaLogCategory = .measure) {
        self.signposter = rawValue
        self.subsystem = subsystem
        self.category = category
    }

    /// The underlying `os.OSSignposter`. Use this for literal-requiring signpost
    /// operations (`emitEvent`/`beginInterval`/`endInterval`/`withIntervalSignpost`).
    public var osSignposter: os.OSSignposter { signposter }

    /// `true` if signposts are enabled for this signposter's subsystem/category.
    public var isEnabled: Bool { signposter.isEnabled }

    /// Returns a fresh, unique ``NebulaSignpostID`` for explicit interval pairing.
    public func makeSignpostID() -> NebulaSignpostID {
        NebulaSignpostID(signposter.makeSignpostID())
    }

    /// Returns a fresh ``NebulaSignpostID`` associated with `object`, so the id
    /// tracks the object's lifetime.
    public func makeSignpostID(from object: AnyObject) -> NebulaSignpostID {
        NebulaSignpostID(signposter.makeSignpostID(from: object))
    }
}
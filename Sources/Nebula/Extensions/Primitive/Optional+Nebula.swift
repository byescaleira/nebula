//
//  Optional+Nebula.swift
//  Nebula
//
//  `Optional` gap-fillers: `or(_:)` (fallback unwrap), `orThrow(_:)` (throw on
//  nil, default ``NebulaNilError``), `isNilOrEmpty` (Collection-constrained).
//  `@autoclosure` + `rethrows` to match stdlib `??`. Natural names per CLAUDE.md.
//  See vault/01-fundamentos/nebula-primitive-extensions.md.
//

import Foundation

extension Optional {
    /// Returns the wrapped value, or `fallback` if `nil`.
    ///
    /// `@autoclosure` + `rethrows` so it is zero-cost and matches stdlib `??`:
    ///
    /// ```swift
    /// let v: Int? = nil
    /// v.or(0)   // 0
    /// ```
    public func or(_ fallback: @autoclosure () throws -> Wrapped) rethrows -> Wrapped {
        switch self {
        case .none: return try fallback()
        case .some(let value): return value
        }
    }

    /// Returns the wrapped value, or throws `error` if `nil`.
    ///
    /// Defaults to ``NebulaNilError`` (a concrete `Sendable` error) so the
    /// `Wrapped == Error` overload collision is avoided. The `@autoclosure`
    /// error is evaluated only when the optional is `nil`.
    public func orThrow(_ error: @autoclosure () -> any Error = NebulaNilError()) throws -> Wrapped {
        switch self {
        case .none: throw error()
        case .some(let value): return value
        }
    }
}

extension Optional where Wrapped: Collection {
    /// `true` if `self` is `nil` or wraps an empty collection.
    public var isNilOrEmpty: Bool {
        switch self {
        case .none: return true
        case .some(let collection): return collection.isEmpty
        }
    }
}
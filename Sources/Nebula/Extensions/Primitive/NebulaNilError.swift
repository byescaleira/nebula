//
//  NebulaNilError.swift
//  Nebula
//
//  A concrete Sendable error thrown when unwrapping a nil Optional. Used as
//  the default for `Optional.orThrow(_:)` so the `Wrapped == Error` overload
//  collision (Paul Calnan) is avoided. See
//  vault/01-fundamentos/nebula-primitive-extensions.md.
//

import Foundation

/// A concrete `Sendable` error thrown when an `Optional` is unexpectedly `nil`.
///
/// Used as the default error for `Optional.orThrow(_:)`. Making it a concrete
/// type (rather than `any Error`) avoids the `Wrapped == Error` overload
/// collision and keeps the error `Sendable` (SE-0302: `any Error` is not
/// `Sendable`).
public struct NebulaNilError: Error, Sendable {
    /// Creates a nil-unwrapping error.
    public init() {}
}
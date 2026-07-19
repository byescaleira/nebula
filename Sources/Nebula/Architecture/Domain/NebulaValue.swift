//
//  NebulaValue.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. The innermost layer: a marker for the
//  simple, immutable, Sendable value structs that cross Clean Architecture
//  boundaries as "simple data structures" (Uncle Bob). `Sendable`, `Equatable`,
//  and `Hashable` are all derived when the conforming struct's fields are —
//  Nebula never authors `@unchecked Sendable` on a value type. See
//  vault/03-padroes/nebula-validation-invariants.md.
//

import Foundation

/// A marker for a `Sendable` value type that crosses Clean Architecture
/// boundaries as "simple data structures".
///
/// Conforming types are immutable `Sendable` value structs (or `actor`s for
/// stateful enterprise rules) that derive `Equatable` and `Hashable` from their
/// fields. Per the dependency rule, the inner layers know nothing of outer
/// layers — a `NebulaValue` carries no framework or presentation concerns.
///
/// ```swift
/// struct Money: NebulaValue {
///     let amount: Decimal
///     let currency: String
/// }
/// ```
///
/// - Note: This is a marker protocol with no additional requirements; it exists
///   so validation rules (`NebulaValidator<T>`) and DTO contracts can constrain
///   to "a value Nebula understands" without coupling to a specific shape.
public protocol NebulaValue: Sendable, Equatable, Hashable {}
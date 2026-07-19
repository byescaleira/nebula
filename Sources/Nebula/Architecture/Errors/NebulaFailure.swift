//
//  NebulaFailure.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. The per-layer error bridge: a
//  `protocol : Error, Sendable` that the layer error open structs (``NebulaDomainError``,
//  ``NebulaValidationError``, ``NebulaRepositoryError``) conform to. The bridge to
//  the closed ``NebulaError/Kind`` enum is **caller-picked** via
//  ``toNebulaError(kind:)``; the default kind a layer maps to is its
//  ``coarseKind``. NO new `NebulaError.Kind` cases are added (the open-struct-
//  over-closed-enum rule scopes to extensible taxonomies like `Kind`).
//  See vault/03-padroes/nebula-domain-error.md and nebula-error-taxonomy-toolkit.md.
//

import Foundation

/// A per-layer `Error` that bridges to the closed ``NebulaError/Kind`` via a
/// caller-picked kind.
///
/// Clean Architecture layers (domain, application/validation, repository) model
/// their own errors as open structs (extensible without a library release) and
/// bridge to the closed `NebulaError.Kind` at the boundary. The bridge kind is
/// **caller-picked** (`toNebulaError(kind:)`) so a layer is never forced into a
/// fixed coarse classification; ``coarseKind`` is the layer's default, used by
/// the dispatch convenience `NebulaError.init(error:)` when no kind is chosen.
///
/// Conforming types MUST be `Sendable` (errors cross actor boundaries — use
/// cases report to presenter ports, repositories surface to use cases). The
/// toolkit's layer structs derive `Sendable`, `Equatable`, and `Hashable` from
/// their fields.
public protocol NebulaFailure: Error, Sendable {
    /// The default ``NebulaError/Kind`` this failure maps to when no kind is
    /// explicitly chosen at the boundary.
    var coarseKind: NebulaError.Kind { get }

    /// Bridges this failure to a ``NebulaError`` under the given kind.
    ///
    /// - Parameter kind: The coarse `NebulaError.Kind` to classify the bridge
    ///   under. Defaults at the boundary to ``coarseKind``.
    func toNebulaError(kind: NebulaError.Kind) -> NebulaError
}

/// A default `coarseKind` of `.unknown` — layer structs override with a more
/// precise mapping.
extension NebulaFailure {
    /// `.unknown` unless the conforming layer overrides.
    public var coarseKind: NebulaError.Kind { .unknown }
}
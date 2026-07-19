//
//  NebulaValidationError.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. A validation-layer error: a
//  parse-don't-validate failure on an input value (a bad field, an out-of-range
//  value, an unmatched pattern). An open struct produced by ``NebulaValidator``
//  rules that bridges to the closed ``NebulaError/Kind`` (default `.validation`)
//  via the caller-picked ``toNebulaError(kind:)``. Derives `Sendable`, `Equatable`,
//  `Hashable` so `#expect(throws:)` can match a specific validation error.
//  See vault/03-padroes/nebula-validation-invariants.md.
//

import Foundation

/// A Clean Architecture **validation-layer** error: a parse-don't-validate
/// failure on an input value.
///
/// Produced by ``NebulaValidator`` rules. An open struct (extensible by a
/// `String` `code` without a library release) conforming to ``NebulaFailure``.
/// `Sendable`, `Equatable`, and `Hashable` are derived from its fields, so a
/// test can assert a specific validation error:
///
/// ```swift
/// #expect(throws: NebulaValidationError(code: "out-of-range", field: "age")) {
///     try validator.validate(input).get()
/// }
/// ```
public struct NebulaValidationError: NebulaFailure, Equatable, Hashable {

    /// A fine-grained, app-defined error code (e.g. `"out-of-range"`).
    public var code: String
    /// The human-facing message.
    public var message: String
    /// The validated field/property the failure is anchored to, if any.
    public var field: String?
    /// Free-form string metadata.
    public var metadata: [String: String]
    /// One nested underlying error (boxed to break struct recursion, reusing
    /// ``NebulaError/Box``).
    public var underlying: NebulaError.Box?

    /// Creates a validation error.
    public init(
        code: String,
        message: String,
        field: String? = nil,
        metadata: [String: String] = [:],
        underlying: NebulaError.Box? = nil
    ) {
        self.code = code
        self.message = message
        self.field = field
        self.metadata = metadata
        self.underlying = underlying
    }

    /// Validation errors are always `.validation`.
    public var coarseKind: NebulaError.Kind { .validation }

    /// Bridges to a ``NebulaError`` under `kind`. The fine `code` and `field`
    /// are preserved as metadata.
    public func toNebulaError(kind: NebulaError.Kind) -> NebulaError {
        var meta = metadata
        meta["NebulaCode"] = code
        if let field { meta["NebulaField"] = field }
        return NebulaError(
            code: NebulaError.Code(domain: "Nebula.NebulaValidationError", code: 0),
            kind: kind,
            message: message,
            metadata: meta,
            underlying: underlying
        )
    }
}
//
//  NebulaDomainError.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. A domain-layer error: a violation of an
//  enterprise business rule (a state the domain forbids regardless of any
//  application or infrastructure). An open struct — consumers invent codes via a
//  `String` without a library release — that bridges to the closed
//  ``NebulaError/Kind`` via the caller-picked ``toNebulaError(kind:)``. Derives
//  `Sendable`, `Equatable`, `Hashable` from its fields so `#expect(throws:)`
//  can match a specific domain error. See vault/03-padroes/nebula-domain-error.md.
//

import Foundation

/// A Clean Architecture **domain-layer** error: a violation of an enterprise
/// business rule.
///
/// An open struct (extensible by a `String` `code` without a library release),
/// conforming to ``NebulaFailure``. `Sendable`, `Equatable`, and `Hashable` are
/// derived from its all-`Sendable`, all-`Hashable` fields, so a test can assert
/// a specific domain error:
///
/// ```swift
/// #expect(throws: NebulaDomainError(code: "insufficient-funds", message: "...")) {
///     try account.withdraw(amount)
/// }
/// ```
public struct NebulaDomainError: NebulaFailure, Equatable, Hashable {

    /// A fine-grained, app-defined error code (e.g. `"insufficient-funds"`).
    public var code: String
    /// The human-facing message.
    public var message: String
    /// Free-form string metadata.
    public var metadata: [String: String]
    /// One nested underlying error (boxed to break struct recursion, reusing
    /// ``NebulaError/Box``).
    public var underlying: NebulaError.Box?

    /// Creates a domain error.
    public init(
        code: String,
        message: String,
        metadata: [String: String] = [:],
        underlying: NebulaError.Box? = nil
    ) {
        self.code = code
        self.message = message
        self.metadata = metadata
        self.underlying = underlying
    }

    /// Domain errors default to `.validation` (an enterprise rule was
    /// violated). Override at the boundary via `toNebulaError(kind:)`.
    public var coarseKind: NebulaError.Kind { .validation }

    /// Bridges to a ``NebulaError`` under `kind`. The fine `code` is preserved
    /// as `metadata["NebulaCode"]`.
    public func toNebulaError(kind: NebulaError.Kind) -> NebulaError {
        var meta = metadata
        meta["NebulaCode"] = code
        return NebulaError(
            code: NebulaError.Code(domain: "Nebula.NebulaDomainError", code: 0),
            kind: kind,
            message: message,
            metadata: meta,
            underlying: underlying
        )
    }
}
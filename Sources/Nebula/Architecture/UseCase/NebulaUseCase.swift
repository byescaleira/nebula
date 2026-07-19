//
//  NebulaUseCase.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. The Use Case seam (Uncle Bob): one
//  `NebulaUseCase<I, O>` per application operation, carrying a typed Input and
//  Output over a `@Sendable` async body. A `Sendable` struct (stateless — ports
//  in `let`); NOT `Equatable` (the `@Sendable` body closure is not `Equatable`,
//  mirroring `NebulaErrorConfiguration`). The CQS role is a closed 2-case enum
//  (a stable binary, not an extensible taxonomy — does not violate the open-
//  struct-over-closed-enum rule, which scopes to extensible taxonomies like
//  `NebulaError.Kind`). Public `execute(_:)` is untyped `throws`; `executeTyped`
//  is the opt-in concrete-`Failure` path (`throws(NebulaError)`, directly
//  testable via `#expect(throws: NebulaError.self)`). See
//  vault/03-padroes/nebula-usecase.md.
//

import Foundation

/// The Command/Query role of a ``NebulaUseCase`` (CQS).
///
/// A closed 2-case `String`-backed enum. CQS is a **stable binary**, not an
/// extensible taxonomy, so a 2-case closed enum does **not** violate the
/// open-struct-over-closed-enum rule (which scopes to extensible taxonomies
/// like ``NebulaError/Kind``). A deprecation-runway to an open struct is
/// available if a third role ever emerges, mirroring the `Kind` comment.
public enum NebulaUseCaseRole: String, Sendable {
    /// A mutating application rule (a command changes state; result is secondary).
    case command
    /// A non-mutating application rule (a query returns data; no state change).
    case query
}

/// The body of a ``NebulaUseCase``: a `@Sendable` async throwing closure from
/// `Input` to `Output`.
public typealias NebulaUseCaseBody<I: Sendable, O: Sendable> = @Sendable (I) async throws -> O

/// A Clean Architecture **Use Case**: one application operation, typed Input
/// to typed Output over a `@Sendable` async body.
///
/// One use case per application operation (Uncle Bob). A `Sendable` struct
/// (stateless — any dependencies are captured in the `@Sendable` body or
/// passed in `Input`), **not** `Equatable` (the `@Sendable` body closure is not
/// `Equatable`, mirroring ``NebulaErrorConfiguration``). The CQS role is the
/// ``NebulaUseCaseRole`` label.
///
/// Public APIs use untyped `throws` (evolution safety); ``executeTyped(_:)`` is
/// the opt-in concrete-`Failure` path — `throws(NebulaError)` — directly
/// testable via `#expect(throws: NebulaError.self)` (Testing `:665`).
///
/// ```swift
/// let withdraw = NebulaUseCase<WithdrawInput, Account>(
///     name: "Withdraw",
///     role: .command
/// ) { input in
///     try await input.account.withdraw(input.amount)
///     return input.account
/// }
///
/// // Untyped (evolution-safe) — call site decides error handling.
/// let result = try await withdraw.execute(input)
///
/// // Typed (opt-in) — narrows to `NebulaError`.
/// let result = try await withdraw.executeTyped(input)
/// ```
public struct NebulaUseCase<I: Sendable, O: Sendable>: Sendable {

    /// A stable, signpost-friendly name for this operation (`StaticString` so it
    /// forwards into `OSSignposter` signposts — see `NebulaMeasureConfiguration`).
    public let name: StaticString
    /// The CQS role of this operation.
    public let role: NebulaUseCaseRole
    /// The `@Sendable` async body.
    public let body: NebulaUseCaseBody<I, O>

    /// Creates a use case.
    public init(
        name: StaticString,
        role: NebulaUseCaseRole = .command,
        body: @escaping NebulaUseCaseBody<I, O>
    ) {
        self.name = name
        self.role = role
        self.body = body
    }

    /// Executes the use case against `input` (untyped `throws`).
    ///
    /// The public, evolution-safe path: a layer error thrown by `body` is
    /// surfaced as-is; the call site decides whether to map it. For a
    /// narrowed `throws(NebulaError)`, use ``executeTyped(_:)``.
    public func execute(_ input: I) async throws -> O {
        try await body(input)
    }

    /// Executes the use case against `input`, narrowing the failure to
    /// ``NebulaError`` (`throws(NebulaError)`, SE-0413).
    ///
    /// A thrown `NebulaError` is preserved as-is; any other `Error` (including
    /// a ``NebulaFailure`` layer error) is lossily bridged via
    /// `NebulaError.init(error:)`. Directly testable:
    ///
    /// ```swift
    /// await #expect(throws: NebulaError.self) {
    ///     try await useCase.executeTyped(badInput)
    /// }
    /// ```
    public func executeTyped(_ input: I) async throws(NebulaError) -> O {
        do {
            return try await body(input)
        } catch let e as NebulaError {
            throw e
        } catch {
            throw NebulaError(error: error)
        }
    }
}
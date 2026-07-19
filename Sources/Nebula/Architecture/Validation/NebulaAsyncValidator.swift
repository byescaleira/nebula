//
//  NebulaAsyncValidator.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. The async validation seam: an
//  `NebulaAsyncValidator<T>` over `AsyncRule`s whose checks may `await` (e.g. a
//  uniqueness check against a ``NebulaReadOnlyRepository``) and `throw` (an I/O
//  failure is distinct from a validation failure). Pure rules use the sync
//  ``NebulaValidator`` so they do not pay an `async` hop. v1 minimal. Sendable
//  derived. See vault/03-padroes/nebula-validation-invariants.md.
//

import Foundation

/// An asynchronous validator over a list of async rules.
///
/// Each ``AsyncRule`` is a `@Sendable` closure from `T` to an optional
/// ``NebulaValidationError`` that may `await` (e.g. a uniqueness check against
/// a ``NebulaReadOnlyRepository``) and `throw` (an I/O failure is distinct from
/// a validation failure — a thrown error propagates out of ``validate(_:)``,
/// it is NOT a `.failure`). ``validate(_:)`` short-circuits on the first
/// failing rule.
///
/// Pure (non-I/O) rules should use the sync ``NebulaValidator`` so they do not
/// pay an `async` hop. `Sendable` is derived (the `@Sendable` rule closures).
///
/// ```swift
/// let uniqueEmail = NebulaAsyncValidator<Account>.AsyncRule { account in
///     let exists = try await repo.find(id: account.id) != nil
///     return exists ? NebulaValidationError(code: "duplicate", field: "email") : nil
/// }
/// ```
public struct NebulaAsyncValidator<T: Sendable>: Sendable {

    /// A single async validation rule: `nil` means the value passes; a thrown
    /// error is an I/O failure (distinct from a validation failure).
    public struct AsyncRule: Sendable {
        /// The rule's async check.
        public let check: @Sendable (T) async throws -> NebulaValidationError?

        /// Creates a rule from an async check closure.
        public init(_ check: @Sendable @escaping (T) async throws -> NebulaValidationError?) {
            self.check = check
        }
    }

    /// The rules, in evaluation order.
    public let rules: [AsyncRule]

    /// Creates a validator from an array of async rules.
    public init(_ rules: [AsyncRule]) {
        self.rules = rules
    }

    /// Creates a validator from a variadic list of async rules.
    public init(_ rules: AsyncRule...) {
        self.rules = rules
    }

    /// Validates `value`, short-circuiting on the first failing rule. A thrown
    /// error (I/O failure) propagates out — it is NOT a `.failure`.
    public func validate(_ value: T) async throws -> Result<T, NebulaValidationError> {
        for rule in rules {
            if let error = try await rule.check(value) { return .failure(error) }
        }
        return .success(value)
    }

    /// Composes two async validators (rules concatenated, left then right).
    public static func + (lhs: NebulaAsyncValidator<T>, rhs: NebulaAsyncValidator<T>) -> NebulaAsyncValidator<T> {
        NebulaAsyncValidator<T>(lhs.rules + rhs.rules)
    }
}
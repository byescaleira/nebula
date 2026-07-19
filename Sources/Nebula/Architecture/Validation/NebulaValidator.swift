//
//  NebulaValidator.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. The sync validation seam: a pure
//  `NebulaValidator<T>` over a list of `Rule`s, parse-don't-validate on the
//  input. `validate(_:)` short-circuits on the FIRST failing rule (returns
//  `Result<T, NebulaValidationError>`); `+` composes validators. v1 minimal —
//  error-accumulating ergonomics are deferred. Sendable derived (the `@Sendable`
//  rule closures). See vault/03-padroes/nebula-validation-invariants.md.
//

import Foundation

/// A synchronous, pure validator over a list of rules.
///
/// Each ``Rule`` is a `@Sendable` closure from `T` to an optional
/// ``NebulaValidationError`` (a rule that returns `nil` passes).
/// ``validate(_:)`` evaluates rules in order and **short-circuits on the first
/// failure** — it returns `.failure` with that error, or `.success(value)` if
/// every rule passes. v1 is minimal: error-accumulating (collect-all-failures)
/// ergonomics are deferred.
///
/// `Sendable` is derived (the `@Sendable` rule closures are Sendable; `[Rule]`
/// is Sendable). NOT `Equatable` (the closures are not `Equatable`).
///
/// ```swift
/// let ageRule = NebulaValidator<Int>.Rule { age in
///     age < 0 ? NebulaValidationError(code: "negative", field: "age") : nil
/// }
/// let validator = NebulaValidator(ageRule)
/// if case .failure(let err) = validator.validate(-1) { … }
/// ```
public struct NebulaValidator<T: Sendable>: Sendable {

    /// A single validation rule: `nil` means the value passes.
    public struct Rule: Sendable {
        /// The rule's check.
        public let check: @Sendable (T) -> NebulaValidationError?

        /// Creates a rule from a check closure.
        public init(_ check: @Sendable @escaping (T) -> NebulaValidationError?) {
            self.check = check
        }
    }

    /// The rules, in evaluation order.
    public let rules: [Rule]

    /// Creates a validator from an array of rules.
    public init(_ rules: [Rule]) {
        self.rules = rules
    }

    /// Creates a validator from a variadic list of rules.
    public init(_ rules: Rule...) {
        self.rules = rules
    }

    /// Validates `value`, short-circuiting on the first failing rule.
    public func validate(_ value: T) -> Result<T, NebulaValidationError> {
        for rule in rules {
            if let error = rule.check(value) { return .failure(error) }
        }
        return .success(value)
    }

    /// Composes two validators (rules concatenated, left then right).
    public static func + (lhs: NebulaValidator<T>, rhs: NebulaValidator<T>) -> NebulaValidator<T> {
        NebulaValidator<T>(lhs.rules + rhs.rules)
    }
}
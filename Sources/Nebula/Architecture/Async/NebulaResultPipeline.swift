//
//  NebulaResultPipeline.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. An async `Result` pipeline over
//  `Result<T, NebulaError>`: `map`/`flatMap`/`recover` as `@Sendable` async
//  transforms. A pure `Sendable` struct (the stored `Result` of a `Sendable`
//  value and a `Sendable` `NebulaError` is `Sendable`). Use-case outputs flow
//  through this rather than ad-hoc do/catch chains. Decision #13. See
//  vault/03-padroes/nebula-async-flow.md.
//

import Foundation

/// A `Sendable` async `Result` pipeline over `Result<T, NebulaError>`.
///
/// Wraps a `Result<T, NebulaError>` and offers `@Sendable` async
/// `map`/`flatMap`/`recover` transforms so a use-case output flows through a
/// chain without ad-hoc do/catch blocks. `map`'s transform may `throw`; a
/// thrown error is bridged via `NebulaError(error:)` (which preserves an
/// existing ``NebulaError`` and bridges ``NebulaFailure`` layer errors).
/// `Sendable` is derived (`Result` of two `Sendable` types is `Sendable`).
///
/// ```swift
/// let pipeline = NebulaResultPipeline(value: 21)
///     let doubled = await pipeline.map { $0 * 2 }   // .success(42)
/// ```
public struct NebulaResultPipeline<T: Sendable>: Sendable {
    /// The wrapped result.
    public let result: Result<T, NebulaError>

    /// Creates a pipeline wrapping `result`.
    public init(_ result: Result<T, NebulaError>) {
        self.result = result
    }

    /// Creates a pipeline wrapping a success value.
    public init(value: T) {
        self.result = .success(value)
    }

    /// Creates a pipeline wrapping a failure.
    public init(error: NebulaError) {
        self.result = .failure(error)
    }

    /// Maps the success value with an async transform that may throw. A thrown
    /// error is bridged to ``NebulaError`` (preserving an existing one); a
    /// `.failure` input short-circuits unchanged.
    public func map<U: Sendable>(
        _ transform: @Sendable (T) async throws -> U
    ) async -> Result<U, NebulaError> {
        switch result {
        case .success(let value):
            do {
                return .success(try await transform(value))
            } catch {
                return .failure(NebulaError(error: error))
            }
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Flat-maps the success value with an async transform that returns a
    /// `Result<U, NebulaError>` (no throw). A `.failure` input short-circuits
    /// unchanged.
    public func flatMap<U: Sendable>(
        _ transform: @Sendable (T) async -> Result<U, NebulaError>
    ) async -> Result<U, NebulaError> {
        switch result {
        case .success(let value):
            return await transform(value)
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Recovers from a `.failure` by falling back to `fallback(error)`;
    /// a `.success` is returned unchanged. Always produces a value.
    public func recover(
        _ fallback: @Sendable (NebulaError) async -> T
    ) async -> T {
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            return await fallback(error)
        }
    }
}
//
//  NebulaStubUseCase.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. A stub use case for tests: returns a
//  fixed ``output`` (`Result<O, NebulaError>`) regardless of input — a canned
//  answer for the system-under-test. A pure `Sendable` struct (no mutable
//  state). Decision #8. See vault/07-metodologia/nebula-test-doubles.md.
//

import Foundation

/// A stub use case: a `Sendable` struct that returns a fixed
/// ``output`` regardless of the input it receives.
///
/// Unlike a ``NebulaSpyUseCase``, a stub records nothing — it is a canned
/// answer for the system-under-test. ``execute(_:)`` returns the value on
/// `.success` and throws the ``NebulaError`` on `.failure`;
/// ``executeTyped(_:)`` mirrors the typed-throws path (decision #10 — the stub
/// stores `Result<O, NebulaError>`, not `Result<O, Error>`).
///
/// ```swift
/// let stub = NebulaStubUseCase<EchoInput, Int>(output: .success(42))
/// let out = try await stub.execute(EchoInput(value: 1)) // 42
/// ```
public struct NebulaStubUseCase<I: Sendable, O: Sendable>: Sendable {
    /// The fixed result returned for every `execute(_:)` call.
    public let output: Result<O, NebulaError>

    /// Creates a stub that always returns `output`.
    public init(output: Result<O, NebulaError>) {
        self.output = output
    }

    /// Returns the stub's fixed output — `.success` value or `.failure` throw.
    @discardableResult
    public func execute(_ input: I) async throws -> O {
        try output.get()
    }

    /// Typed-throws variant (mirrors ``NebulaUseCase/executeTyped(_:)``): on
    /// `.failure` the stored ``NebulaError`` is rethrown as typed `NebulaError`.
    @discardableResult
    public func executeTyped(_ input: I) async throws(NebulaError) -> O {
        switch output {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }
}
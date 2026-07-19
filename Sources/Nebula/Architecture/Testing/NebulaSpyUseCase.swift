//
//  NebulaSpyUseCase.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. A spy use case for tests: records every
//  input it receives, then delegates to a `body` closure. A `final class` with a
//  `let Mutex<[I]>` invocations buffer; `Sendable` is **derived** (a `final class`
//  whose stored properties are all immutable `let` of `Sendable` types synthesizes
//  `Sendable` — no `@unchecked`), so a spy can be shared across tasks. A
//  `Mutex`-typed stored property would propagate `~Copyable` to an owning *struct*,
//  so the mutable buffer lives in a class (mirrors ``NebulaMemoryLogHandler``'s
//  class-over-struct choice; unlike that handler's `var` ring buffer, this spy's
//  state is a single `let` Mutex, so it derives Sendable cleanly). Decision #8.
//  See vault/07-metodologia/nebula-test-doubles.md.
//

import Foundation
import Synchronization

/// A spy use case: records every input it receives, then delegates to `body`.
///
/// A `final class` with a `let Mutex<[I]>` invocations buffer. `Sendable` is
/// **derived** — a `final class` whose stored properties are all immutable `let`
/// of `Sendable` types synthesizes `Sendable` (no `@unchecked`), so a spy can be
/// shared across tasks. A `Mutex`-typed stored property would propagate
/// `~Copyable` to an owning *struct*, so the mutable buffer lives in a class.
/// Use ``callCount``/``inputs()`` to assert on what the system-under-test did.
///
/// ```swift
/// let spy = NebulaSpyUseCase<Echo, Int> { $0.value * 2 }
/// _ = try await spy.execute(Echo(value: 21))
/// #expect(spy.callCount == 1)
/// #expect(spy.inputs().first?.value == 21)
/// ```
public final class NebulaSpyUseCase<I: Sendable, O: Sendable>: Sendable {
    private let invocations = Mutex<[I]>([])
    /// The body the spy delegates to after recording the input.
    public let body: @Sendable (I) async throws -> O

    /// Creates a spy that records inputs and delegates to `body`.
    public init(body: @Sendable @escaping (I) async throws -> O) {
        self.body = body
    }

    /// The number of inputs recorded so far.
    public var callCount: Int {
        invocations.withLock { $0.count }
    }

    /// A snapshot of the recorded inputs, in call order.
    public func inputs() -> [I] {
        invocations.withLock { $0 }
    }

    /// Records `input` then delegates to ``body``.
    @discardableResult
    public func execute(_ input: I) async throws -> O {
        invocations.withLock { $0.append(input) }
        return try await body(input)
    }
}
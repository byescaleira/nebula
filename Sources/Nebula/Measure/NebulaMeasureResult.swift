//
//  NebulaMeasureResult.swift
//  Nebula
//
//  A Sendable, Equatable snapshot of a single `bench()` run: the signpost
//  label, the iteration count, the total elapsed `Duration`, and derived
//  per-iteration / component accessors. Carried into the
//  `NebulaMeasureConfiguration.handler` fan-out. See
//  vault/01-fundamentos/nebula-standardize-measure.md.
//

import Foundation
import _Concurrency

/// A `Sendable` snapshot of one `NebulaMeasureConfiguration.bench(_:iterations:warmup:operation:)` run.
///
/// Stores the signpost label (`name`), the iteration count, and the total
/// elapsed `Duration`. The derived ``perIteration`` and ``components``
/// accessors are computed on demand (not stored), so synthesized `Equatable`
/// compares only `name` / `iterations` / `total` — the three load-bearing
/// fields. All three are `Sendable` and `Equatable`, so both conformances are
/// derived (no `@unchecked`, no authored `==`).
public struct NebulaMeasureResult: Sendable, Equatable {
    /// The signpost label the run was timed under (a `StaticString` literal
    /// promoted to `String` at the call site).
    public let name: String
    /// The number of timed iterations (warmup runs are excluded).
    public let iterations: Int
    /// The total elapsed duration across all timed iterations.
    public let total: Duration

    /// Creates a measure result.
    ///
    /// - Parameters:
    ///   - name: The signpost label the run was timed under.
    ///   - iterations: The number of timed iterations.
    ///   - total: The total elapsed duration across all timed iterations.
    public init(name: String, iterations: Int, total: Duration) {
        self.name = name
        self.iterations = iterations
        self.total = total
    }

    /// The mean duration per iteration (`total / iterations`).
    ///
    /// Uses `Duration`'s `/ (Duration, Int) -> Duration` overload (verified
    /// against the Swift 6.4 / Xcode 27 Beta 3 toolchain — both the `Int` and
    /// `Double` overloads exist; the `Int` form preserves the full seconds +
    /// attoseconds precision of the underlying `Duration` representation).
    public var perIteration: Duration { total / iterations }

    /// The `(seconds, attoseconds)` decomposition of ``total``, forwarded to
    /// `Duration.components`.
    public var components: (seconds: Int64, attoseconds: Int64) { total.components }
}
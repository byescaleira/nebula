//
//  NebulaMeasureConfiguration.swift
//  Nebula
//
//  The Nebula measure/timing configuration: a Sendable value carrying the
//  timing contract (clock, signposter, enabled flag, and a @Sendable handler
//  for fan-out) PLUS the `measure(_:)` / `bench(_:)` entry points — mirroring
//  how NebulaLogConfiguration carries `log(_:_:)` on the config itself. Fluent
//  `.with*` builders mirror the Cosmos sibling's CosmosLogConfiguration
//  WITHOUT SwiftUI @Entry/@Observable. See
//  vault/01-fundamentos/nebula-standardize-measure.md.
//

import Foundation
import os
import _Concurrency

/// The Nebula measure/timing configuration.
///
/// A `Sendable` value (NOT `Equatable` — it stores a `@Sendable` closure,
/// which cannot be compared, mirroring ``NebulaLogConfiguration`` and
/// ``NebulaErrorConfiguration``) describing how work is timed and routed:
///
/// - ``clock`` is the timing source (default `ContinuousClock`, the wall-clock
///   clock WWDC22 recommends for human-relative durations; pass
///   `SuspendingClock()` for machine-relative timing that pauses with the
///   process);
/// - ``signposter`` optionally wraps each `measure` run in an Instruments
///   signpost interval (nil by default — a foundation does not force
///   Instruments overhead on consumers; opt in via
///   ``withSignposter(_:)`` or by sharing a logger's signposter);
/// - ``isEnabled`` gates BOTH the secondary ``handler`` fan-out AND the
///   signpost emission — timing itself ALWAYS runs regardless (a measurement
///   that did not measure is worthless). This keeps the handler's cost
///   (e.g. an in-memory sink for tests) zero when disabled while preserving
///   the returned `Duration`;
/// - ``handler`` is invoked with a ``NebulaMeasureResult`` on every
///   `bench()` run (not on `measure(_:)`, which returns the `Duration`
///   directly).
///
/// The contract follows the Cosmos sibling pattern — `Sendable` struct +
/// `@Sendable` handler + fluent `.with*` builders — but with no SwiftUI
/// `@Entry`/`@Observable`: a foundation does not own UI-thread affinity, so
/// configurations are constructed and passed explicitly.
///
/// ## Signpost name forwarding
///
/// `measure(_:)` / `bench(_:)` take `name: StaticString` and forward it to
/// `OSSignposter.withIntervalSignpost` / `beginInterval` / `endInterval`.
/// Forwarding a `StaticString` parameter into those call sites COMPILES AND
/// RUNS on the Swift 6.4 / Xcode 27 Beta 3 toolchain (verified — see the
/// pre-verified API notes in `CLAUDE.md`). The ``NebulaSignposter``/
/// `signposter` escape hatch is used directly so the stable
/// `Logging/NebulaSignposter.swift` is not modified.
public struct NebulaMeasureConfiguration: Sendable {
    /// The timing source. Defaults to `ContinuousClock()` (wall-clock; advances
    /// during system sleep). Pass `SuspendingClock()` for machine-relative
    /// timing that pauses with the process.
    public let clock: any Clock<Duration>
    /// An optional ``NebulaSignposter`` for Instruments-integrated intervals.
    /// `nil` by default — opt in via ``withSignposter(_:)``.
    public let signposter: NebulaSignposter?
    /// Whether the secondary ``handler`` fan-out AND signpost emission are
    /// enabled. Timing itself always runs regardless of this flag.
    public let isEnabled: Bool
    /// Invoked with a ``NebulaMeasureResult`` on every `bench()` run, gated on
    /// ``isEnabled``. The default `{ _ in }` is capture-free and trivially
    /// `Sendable`.
    public let handler: @Sendable (NebulaMeasureResult) -> Void

    /// Creates a measure configuration.
    ///
    /// - Parameters:
    ///   - clock: The timing source. Defaults to `ContinuousClock()`.
    ///   - signposter: An optional `NebulaSignposter` for signpost intervals.
    ///     `nil` disables signposts (the default).
    ///   - isEnabled: Whether the secondary handler fan-out and signpost
    ///     emission are enabled. Defaults to `true`.
    ///   - handler: Invoked with a `NebulaMeasureResult` on every `bench()`
    ///     run, gated on `isEnabled`. Defaults to a capture-free no-op.
    public init(
        clock: any Clock<Duration> = ContinuousClock(),
        signposter: NebulaSignposter? = nil,
        isEnabled: Bool = true,
        handler: @escaping @Sendable (NebulaMeasureResult) -> Void = { _ in }
    ) {
        self.clock = clock
        self.signposter = signposter
        self.isEnabled = isEnabled
        self.handler = handler
    }

    /// The default configuration. Idempotent via the once-token `static let`
    /// initializer side-effect (no lock primitive). Override pieces with the
    /// `.with*` builders. Signposts are OFF by default — a foundation should
    /// not force Instruments overhead; consumers opt in via
    /// ``withSignposter(_:)``.
    public static let `default` = NebulaMeasureConfiguration()

    // MARK: - Fluent builders

    /// Returns a copy with the clock replaced.
    public func withClock(_ clock: any Clock<Duration>) -> NebulaMeasureConfiguration {
        .init(clock: clock, signposter: signposter, isEnabled: isEnabled, handler: handler)
    }

    /// Returns a copy with the signposter replaced (`nil` disables signposts).
    public func withSignposter(_ signposter: NebulaSignposter?) -> NebulaMeasureConfiguration {
        .init(clock: clock, signposter: signposter, isEnabled: isEnabled, handler: handler)
    }

    /// Returns a copy with `isEnabled` replaced.
    public func withEnabled(_ isEnabled: Bool) -> NebulaMeasureConfiguration {
        .init(clock: clock, signposter: signposter, isEnabled: isEnabled, handler: handler)
    }

    /// Returns a copy with the handler replaced.
    public func withHandler(_ handler: @escaping @Sendable (NebulaMeasureResult) -> Void) -> NebulaMeasureConfiguration {
        .init(clock: clock, signposter: signposter, isEnabled: isEnabled, handler: handler)
    }

    // MARK: - Measurement

    /// Times `operation` once under ``clock`` and — if a ``signposter`` is
    /// configured and ``isEnabled`` — wraps it in a signpost interval via
    /// `OSSignposter.withIntervalSignpost`. Timing always runs.
    ///
    /// - Parameters:
    ///   - name: The signpost label (`StaticString` literal — forwarded into
    ///     `withIntervalSignpost`, which compiles on this toolchain).
    ///   - operation: The synchronous work to time.
    /// - Returns: The operation's result and the elapsed `Duration`.
    public func measure<T>(
        _ name: StaticString,
        operation: () throws -> T
    ) rethrows -> (T, Duration) {
        var result: T!
        let elapsed = try clock.measure {
            if let sp = signposter?.osSignposter, isEnabled {
                result = try sp.withIntervalSignpost(name) { try operation() }
            } else {
                result = try operation()
            }
        }
        return (result, elapsed)
    }

    /// Async variant of ``measure(_:operation:)``. Uses manual
    /// `beginInterval`/`endInterval` bracketing because
    /// `OSSignposter.withIntervalSignpost` has no async variant (verified).
    /// `defer` ensures the interval ends even on throw.
    ///
    /// - Parameters:
    ///   - name: The signpost label (`StaticString` literal).
    ///   - operation: The asynchronous work to time.
    /// - Returns: The operation's result and the elapsed `Duration`.
    public func measure<T>(
        _ name: StaticString,
        operation: () async throws -> T
    ) async rethrows -> (T, Duration) {
        var result: T!
        // The async `Clock.measure` overload requires a `() async throws -> Void`
        // body (annotated explicitly so a body returning `T` does not resolve to
        // the sync overload). `Clock.measure` is `rethrows` → needs `try`.
        let elapsed = try await clock.measure { () async throws -> Void in
            if let sp = signposter?.osSignposter, isEnabled {
                let state = sp.beginInterval(name)
                defer { sp.endInterval(name, state) }
                result = try await operation()
            } else {
                result = try await operation()
            }
        }
        return (result, elapsed)
    }

    /// A quick micro-benchmark: runs `warmup` untimed invocations followed by
    /// `iterations` timed invocations under ``clock``, and returns a
    /// ``NebulaMeasureResult``. Invokes ``handler`` with the result if
    /// ``isEnabled``.
    ///
    /// - Note: This is not statistically rigorous — no p50/p99, no
    ///   clock-resolution check; runs on the caller's thread. Use it for quick
    ///   relative comparisons, not publication-grade numbers.
    ///
    /// - Parameters:
    ///   - name: The signpost label.
    ///   - iterations: The number of timed iterations. Defaults to `10`.
    ///   - warmup: The number of untimed warmup iterations. Defaults to `0`.
    ///   - operation: The synchronous work to time.
    /// - Returns: A `NebulaMeasureResult` summarizing the run.
    public func bench(
        _ name: StaticString,
        iterations: Int = 10,
        warmup: Int = 0,
        operation: () throws -> Void
    ) rethrows -> NebulaMeasureResult {
        for _ in 0..<warmup { try operation() }
        let total = try clock.measure { for _ in 0..<iterations { try operation() } }
        // `StaticString` has no lossless `String(_:)` initializer (only
        // `String(describing:)`/`String(reflecting:)`); `String(describing:)`
        // returns the literal's UTF-8 contents verbatim.
        let result = NebulaMeasureResult(name: String(describing: name), iterations: iterations, total: total)
        if isEnabled { handler(result) }
        return result
    }
}
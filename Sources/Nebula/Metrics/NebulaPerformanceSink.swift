//
//  NebulaPerformanceSink.swift
//  Nebula
//
//  Wave N19e — CloudKit-backed observability suite. The performance sink: a
//  stateless enum (derived `Sendable` — no stored state) that produces a
//  `@Sendable (NebulaMeasureResult) -> Void` suitable to install as
//  `NebulaMeasureConfiguration.handler`, routing each timing result into
//  `NebulaMetricsConfiguration.record(_:kind:value:attributes:)`. This bridges
//  the Measure subsystem (N19 / Wave D) and the Metrics subsystem (N19a) without
//  coupling them: Measure emits a `NebulaMeasureResult`; the sink adapts it to a
//  `.timing` `NebulaMetricEvent`. See
//  vault/03-padroes/nebula-cloudkit-observability.md.
//

import Foundation
import _Concurrency

/// A stateless adapter that routes ``NebulaMeasureResult`` timing snapshots into
/// a ``NebulaMetricsConfiguration`` as `.timing` metric events.
///
/// `NebulaPerformanceSink` is an enum (no cases) used as a namespace — it carries
/// no stored state, so `Sendable` is derived (no `@unchecked`). The
/// ``handler(via:prefix:)`` / ``handler(via:mapping:)`` static methods return a
/// `@Sendable (NebulaMeasureResult) -> Void` closure that captures only a
/// `Sendable` value (`NebulaMetricsConfiguration`) and (for the mapping overload)
/// a `@Sendable` closure, so the returned closure derives `Sendable` without any
/// `@unchecked` annotation.
///
/// Install the returned closure as `NebulaMeasureConfiguration.handler`:
/// ```swift
/// let metrics = NebulaMetricsConfiguration.default.withHandler { event in
///     NebulaMetricsConfig.record(event)
/// }
/// let measure = NebulaMeasureConfiguration.default.withHandler(
///     NebulaPerformanceSink.handler(via: metrics, prefix: "boot")
/// )
/// ```
///
/// The default mapping emits a `.timing` event with:
/// - `name` = `prefix` prepended (`"\(prefix).\(result.name)"`) when a prefix is
///   supplied, otherwise `result.name` unchanged;
/// - `value` = `result.perIteration` converted to `Double` seconds via
///   `Duration.components` (`Double(seconds) + Double(attoseconds) / 1e18`,
///   matching the `NebulaMetrics.timing(_:duration:attributes:)` ergonomics);
/// - `attributes` = `["iterations": .int(result.iterations)]`.
public enum NebulaPerformanceSink {

    /// Returns a `@Sendable` handler that routes each ``NebulaMeasureResult`` into
    /// `metrics` as a `.timing` event, with an optional `prefix` namespace.
    ///
    /// The default mapping builds a ``NebulaMetricEvent`` of kind `.timing`:
    /// - `name` = `prefix.map { "\($0).\(result.name)" } ?? result.name`;
    /// - `value` = `result.perIteration` in seconds (`Duration` → `Double` via
    ///   `Duration.components`, matching ``NebulaMetrics/timing(_:duration:attributes:)``);
    /// - `attributes` = `["iterations": .int(result.iterations)]`.
    ///
    /// The returned closure is the capture of a `Sendable` struct
    /// (`NebulaMetricsConfiguration`) plus a `String?` (also `Sendable`) inside a
    /// `@Sendable` closure, so `Sendable` is derived — no `@unchecked`.
    ///
    /// - Parameters:
    ///   - metrics: The metrics configuration to route into. Captured by value
    ///     (a `Sendable` struct), so the closure is safe to ship across
    ///     isolation boundaries.
    ///   - prefix: An optional namespace prepended to `result.name` with a `.`
    ///     separator. `nil` by default — emit `result.name` unchanged.
    /// - Returns: A `@Sendable` closure suitable for
    ///   `NebulaMeasureConfiguration.handler`.
    public static func handler(
        via metrics: NebulaMetricsConfiguration,
        prefix: String? = nil
    ) -> @Sendable (NebulaMeasureResult) -> Void {
        handler(via: metrics) { result in
            let name = prefix.map { "\($0).\(result.name)" } ?? result.name
            let (seconds, attoseconds) = result.perIteration.components
            let perIterationSeconds = Double(seconds) + Double(attoseconds) / 1e18
            return NebulaMetricEvent(
                name: name,
                kind: .timing,
                value: perIterationSeconds,
                attributes: ["iterations": .int(result.iterations)]
            )
        }
    }

    /// Returns a `@Sendable` handler that routes each ``NebulaMeasureResult``
    /// through a caller-supplied `mapping` closure into `metrics` as a
    /// ``NebulaMetricEvent``.
    ///
    /// Use this overload when the default `.timing` mapping is too rigid — e.g.
    /// when you want `.histogram` kind, a different attribute shape, or a name
    /// transform that does not fit the `prefix` convention. The `mapping` closure
    /// is `@Sendable` so the returned closure is the capture of two `Sendable`
    /// values (`NebulaMetricsConfiguration` and the `@Sendable` closure) —
    /// `Sendable` is derived, no `@unchecked`.
    ///
    /// - Parameters:
    ///   - metrics: The metrics configuration to route into. Captured by value
    ///     (a `Sendable` struct).
    ///   - mapping: A `@Sendable` closure translating a `NebulaMeasureResult`
    ///     into a `NebulaMetricEvent`. The result is passed to
    ///     `NebulaMetricsConfiguration.record(_:)`, which gates on `isEnabled`.
    /// - Returns: A `@Sendable` closure suitable for
    ///   `NebulaMeasureConfiguration.handler`.
    public static func handler(
        via metrics: NebulaMetricsConfiguration,
        mapping: @escaping @Sendable (NebulaMeasureResult) -> NebulaMetricEvent
    ) -> @Sendable (NebulaMeasureResult) -> Void {
        { result in metrics.record(mapping(result)) }
    }
}
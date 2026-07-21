//
//  NebulaMetrics.swift
//  Nebula
//
//  Wave N19a — CloudKit-backed observability suite. The metrics port: a
//  `Sendable` protocol with a single low-level requirement (`record(_:)`) plus
//  default-extension typed ergonomics (`increment` / `observe` / `gauge` /
//  `timing`), mirroring the `NebulaFeatureFlags` port shape (one requirement +
//  derived ergonomics). A CloudKit adapter is *another conformer*, not new
//  architecture. See vault/03-padroes/nebula-cloudkit-observability.md.
//

import Foundation
import _Concurrency

/// A `Sendable` metrics port.
///
/// The architecture seam for recording metric events. The contract is
/// intentionally tiny — a single `record(_:)` requirement carrying a
/// ``NebulaMetricEvent`` — so an app can swap the backend (an in-memory sink
/// for tests, a CloudKit adapter for production, an OTel exporter) without
/// reimplementing the typed ergonomics.
///
/// Everything else is a **default extension** built on `record(_:)`:
/// - ``increment(_:by:attributes:)`` — a `.counter` event;
/// - ``observe(_:value:attributes:)`` — a `.histogram` observation;
/// - ``gauge(_:value:attributes:)`` — a `.gauge` snapshot;
/// - ``timing(_:duration:attributes:)`` — a `.timing` event, converting a
///   `Duration` to `Double` seconds via `Duration.components`.
public protocol NebulaMetrics: Sendable {

    /// Records a metric event. The single low-level requirement; all other
    /// ergonomics are derived in the default extension.
    func record(_ event: NebulaMetricEvent)
}

public extension NebulaMetrics {

    /// Records a `.counter` event — a monotonically increasing value.
    ///
    /// - Parameters:
    ///   - name: The metric name.
    ///   - by: The increment amount. Defaults to `1`.
    ///   - attributes: Per-event typed dimensions. Empty by default.
    func increment(
        _ name: String,
        by: Int = 1,
        attributes: [String: NebulaMetricValue] = [:]
    ) {
        record(NebulaMetricEvent(name: name, kind: .counter, value: Double(by), attributes: attributes))
    }

    /// Records a `.histogram` observation — a sampled magnitude for a
    /// distribution.
    ///
    /// - Parameters:
    ///   - name: The metric name.
    ///   - value: The observed magnitude.
    ///   - attributes: Per-event typed dimensions. Empty by default.
    func observe(
        _ name: String,
        value: Double,
        attributes: [String: NebulaMetricValue] = [:]
    ) {
        record(NebulaMetricEvent(name: name, kind: .histogram, value: value, attributes: attributes))
    }

    /// Records a `.gauge` event — an instantaneous, non-monotonic value.
    ///
    /// - Parameters:
    ///   - name: The metric name.
    ///   - value: The instantaneous magnitude.
    ///   - attributes: Per-event typed dimensions. Empty by default.
    func gauge(
        _ name: String,
        value: Double,
        attributes: [String: NebulaMetricValue] = [:]
    ) {
        record(NebulaMetricEvent(name: name, kind: .gauge, value: value, attributes: attributes))
    }

    /// Records a `.timing` event — a measured duration, converted to `Double`
    /// seconds.
    ///
    /// The `Duration` → `Double` conversion uses `Duration.components`
    /// (`seconds:attoseconds`): `Double(seconds) + Double(attoseconds) / 1e18`.
    /// This preserves the full `Duration` precision into the `Double` (the
    /// attoseconds term is sub-ULP at most practical magnitudes; the seconds
    /// term dominates).
    ///
    /// - Parameters:
    ///   - name: The metric name.
    ///   - duration: The measured duration.
    ///   - attributes: Per-event typed dimensions. Empty by default.
    func timing(
        _ name: String,
        duration: Duration,
        attributes: [String: NebulaMetricValue] = [:]
    ) {
        let (seconds, attoseconds) = duration.components
        let secondsValue = Double(seconds) + Double(attoseconds) / 1e18
        record(NebulaMetricEvent(name: name, kind: .timing, value: secondsValue, attributes: attributes))
    }
}

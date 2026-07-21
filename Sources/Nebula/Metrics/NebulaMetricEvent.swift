//
//  NebulaMetricEvent.swift
//  Nebula
//
//  Wave N19a — CloudKit-backed observability suite. The metric event envelope:
//  a kind (counter / histogram / gauge / timing), a scalar value, a timestamp,
//  and a typed `attributes` map. The single low-level payload carried by the
//  ``NebulaMetrics`` port. See vault/03-padroes/nebula-cloudkit-observability.md.
//

import Foundation

/// The kind of a ``NebulaMetricEvent``.
///
/// - ``counter``: a monotonically increasing value (e.g. requests served).
/// - ``histogram``: an observation of a distribution (e.g. request size).
/// - ``gauge``: an instantaneous, non-monotonic value (e.g. queue depth).
/// - ``timing``: a measured duration in seconds (e.g. request latency).
public enum NebulaMetricKind: Sendable, Equatable, Hashable {
    /// A monotonically increasing value.
    case counter
    /// An observation sampled into a distribution.
    case histogram
    /// An instantaneous, non-monotonic value.
    case gauge
    /// A measured duration in seconds.
    case timing
}

/// A `Sendable` metric event: the single payload carried by the ``NebulaMetrics``
/// port.
///
/// Stores the metric `name`, its ``NebulaMetricKind``, a scalar `value` (the
/// unit depends on the kind — counts for `counter`, seconds for `timing`, the
/// sampled magnitude for `histogram` / `gauge`), a `timestamp`, and a typed
/// `attributes` map (``NebulaMetricValue``) for per-event dimensions.
///
/// All four fields are `Sendable`, `Equatable`, and `Hashable`, so all three
/// conformances are derived (no `@unchecked`, no authored `==` / `hash(into:)`).
public struct NebulaMetricEvent: Sendable, Equatable, Hashable {
    /// The metric name (a stable, dotted identifier, e.g. `request.latency`).
    public let name: String
    /// The metric kind — selects how a backend aggregates `value`.
    public let kind: NebulaMetricKind
    /// The scalar value. Units are kind-dependent (counts, seconds, magnitude).
    public let value: Double
    /// The event timestamp. Defaults to `Date()` at construction time.
    public let timestamp: Date
    /// Per-event typed dimensions. Empty by default.
    public let attributes: [String: NebulaMetricValue]

    /// Creates a metric event.
    ///
    /// - Parameters:
    ///   - name: The metric name.
    ///   - kind: The metric kind.
    ///   - value: The scalar value (units are kind-dependent).
    ///   - timestamp: The event timestamp. Defaults to `Date()` (the default
    ///     argument is a fresh `Date()` per call — not a `static let`
    ///     side-effect, so each event gets its own capture time).
    ///   - attributes: Per-event typed dimensions. Empty by default.
    public init(
        name: String,
        kind: NebulaMetricKind,
        value: Double,
        timestamp: Date = Date(),
        attributes: [String: NebulaMetricValue] = [:]
    ) {
        self.name = name
        self.kind = kind
        self.value = value
        self.timestamp = timestamp
        self.attributes = attributes
    }
}

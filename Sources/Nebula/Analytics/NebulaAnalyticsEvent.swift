//
//  NebulaAnalyticsEvent.swift
//  Nebula
//
//  Wave N19b — CloudKit-backed observability suite. The analytics event
//  envelope: a name, a typed `properties` map (reusing ``NebulaMetricValue``
//  so analytics and metrics share one attribute sum type), and a timestamp.
//  The single low-level payload carried by the ``NebulaAnalytics`` port. See
//  vault/03-padroes/nebula-cloudkit-observability.md.
//

import Foundation

/// A `Sendable` analytics event: the single payload carried by the
/// ``NebulaAnalytics`` port.
///
/// Stores the event `name` (a stable, dotted identifier, e.g.
/// `signup.completed`), a typed `properties` map (``NebulaMetricValue`` — the
/// same sum type used by ``NebulaMetricEvent``, so analytics and metrics share
/// one attribute vocabulary without a second type), and a `timestamp`.
///
/// All three fields are `Sendable`, `Equatable`, and `Hashable`, so all three
/// conformances are derived (no `@unchecked`, no authored `==` /
/// `hash(into:)`).
public struct NebulaAnalyticsEvent: Sendable, Equatable, Hashable {
    /// The event name (a stable, dotted identifier, e.g. `signup.completed`).
    public let name: String
    /// Per-event typed properties. Reuses ``NebulaMetricValue`` so analytics
    /// and metrics share one attribute sum type. Empty by default.
    public let properties: [String: NebulaMetricValue]
    /// The event timestamp. Defaults to `Date()` at construction time.
    public let timestamp: Date

    /// Creates an analytics event.
    ///
    /// - Parameters:
    ///   - name: The event name.
    ///   - properties: Per-event typed properties. Empty by default.
    ///   - timestamp: The event timestamp. Defaults to `Date()` (the default
    ///     argument is a fresh `Date()` per call — not a `static let`
    ///     side-effect, so each event gets its own capture time).
    public init(
        name: String,
        properties: [String: NebulaMetricValue] = [:],
        timestamp: Date = Date()
    ) {
        self.name = name
        self.properties = properties
        self.timestamp = timestamp
    }
}

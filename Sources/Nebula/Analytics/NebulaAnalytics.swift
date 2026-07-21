//
//  NebulaAnalytics.swift
//  Nebula
//
//  Wave N19b — CloudKit-backed observability suite. The analytics port: a
//  `Sendable` protocol with a single low-level requirement (`track(_:)`) plus
//  default-extension typed ergonomics (`track(_:properties:)` / `screen(_:)` /
//  `identify(_:)`), mirroring the ``NebulaMetrics`` port shape (one requirement
//  + derived ergonomics). A CloudKit adapter is *another conformer*, not new
//  architecture. See vault/03-padroes/nebula-cloudkit-observability.md.
//

import Foundation

/// A `Sendable` analytics port.
///
/// The architecture seam for recording analytics events. The contract is
/// intentionally tiny — a single `track(_:)` requirement carrying a
/// ``NebulaAnalyticsEvent`` — so an app can swap the backend (an in-memory
/// sink for tests, a CloudKit adapter for production, a third-party SDK
/// wrapper) without reimplementing the typed ergonomics.
///
/// Everything else is a **default extension** built on `track(_:)`:
/// - ``track(_:properties:)`` — a named event with properties;
/// - ``screen(_:properties:)`` — a screen-view event (name prefixed
///   `screen.` for a stable namespace);
/// - ``identify(_:properties:)`` — an identity-association event.
public protocol NebulaAnalytics: Sendable {

    /// Tracks an analytics event. The single low-level requirement; all other
    /// ergonomics are derived in the default extension.
    func track(_ event: NebulaAnalyticsEvent)
}

public extension NebulaAnalytics {

    /// Tracks a named event with the given properties. Builds a
    /// ``NebulaAnalyticsEvent`` (timestamp defaults to `Date()` at the call
    /// site) and forwards it to ``track(_:)``.
    ///
    /// - Parameters:
    ///   - name: The event name.
    ///   - properties: Per-event typed properties. Empty by default.
    func track(
        _ name: String,
        properties: [String: NebulaMetricValue] = [:]
    ) {
        track(NebulaAnalyticsEvent(name: name, properties: properties))
    }

    /// Tracks a screen-view event. The event name is prefixed `screen.` so
    /// screen views form a stable namespace in downstream sinks (a CloudKit
    /// adapter or any other backend can group them without parsing the name).
    ///
    /// - Parameters:
    ///   - name: The screen name (without the `screen.` prefix).
    ///   - properties: Per-event typed properties. Empty by default.
    func screen(
        _ name: String,
        properties: [String: NebulaMetricValue] = [:]
    ) {
        track("screen.\(name)", properties: properties)
    }

    /// Tracks an identity-association event. The `userID` is carried in the
    /// `properties` under the `userID` key (a `.string` value) so downstream
    /// sinks do not need a dedicated event shape; additional traits go in
    /// `properties`. The event name is the stable identifier `identify`.
    ///
    /// - Parameters:
    ///   - userID: The user identifier to associate with the current session.
    ///   - properties: Additional traits. Empty by default. Merged with the
    ///     `userID` entry (caller-supplied `userID` key wins on collision).
    func identify(
        _ userID: String,
        properties: [String: NebulaMetricValue] = [:]
    ) {
        var merged = properties
        merged["userID"] = .string(userID)
        track(NebulaAnalyticsEvent(name: "identify", properties: merged))
    }
}

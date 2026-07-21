//
//  NebulaMetricsConfiguration.swift
//  Nebula
//
//  Wave N19a — CloudKit-backed observability suite. The metrics configuration:
//  a `Sendable` value carrying the `isEnabled` gate and a `@Sendable` handler
//  for fan-out, PLUS the `record(_:)` entry point — mirroring how
//  `NebulaMeasureConfiguration` carries `bench(_:)` on the config itself. Fluent
//  `.with*` builders mirror the Cosmos sibling's configuration shape WITHOUT
//  SwiftUI `@Entry`/`@Observable`. See
//  vault/03-padroes/nebula-cloudkit-observability.md.
//

import Foundation

/// The Nebula metrics configuration.
///
/// A `Sendable` value (NOT `Equatable` — it stores a `@Sendable` closure, which
/// cannot be compared, mirroring ``NebulaMeasureConfiguration`` and
/// ``NebulaLogConfiguration``) describing how metric events are routed:
/// - ``isEnabled`` gates the secondary ``handler`` fan-out — recording itself
///   ALWAYS constructs the ``NebulaMetricEvent`` but, when disabled, the
///   handler is not invoked (zero fan-out cost);
/// - ``handler`` is invoked with a ``NebulaMetricEvent`` on every `record()`
///   call, gated on ``isEnabled``. The default `{ _ in }` is capture-free and
///   trivially `Sendable`.
///
/// The contract follows the Cosmos sibling pattern — `Sendable` struct +
/// `@Sendable` handler + fluent `.with*` builders — but with no SwiftUI
/// `@Entry`/`@Observable`: a foundation does not own UI-thread affinity, so
/// configurations are constructed and passed explicitly.
public struct NebulaMetricsConfiguration: Sendable {
    /// Whether the secondary ``handler`` fan-out is enabled. Event
    /// construction still runs regardless of this flag; the handler is skipped
    /// when disabled.
    public let isEnabled: Bool
    /// Invoked with a ``NebulaMetricEvent`` on every `record()` call, gated on
    /// ``isEnabled``. The default `{ _ in }` is capture-free and trivially
    /// `Sendable`.
    public let handler: @Sendable (NebulaMetricEvent) -> Void

    /// Creates a metrics configuration.
    ///
    /// - Parameters:
    ///   - isEnabled: Whether the secondary handler fan-out is enabled.
    ///     Defaults to `true`.
    ///   - handler: Invoked with a `NebulaMetricEvent` on every `record()`
    ///     call, gated on `isEnabled`. Defaults to a capture-free no-op.
    public init(
        isEnabled: Bool = true,
        handler: @escaping @Sendable (NebulaMetricEvent) -> Void = { _ in }
    ) {
        self.isEnabled = isEnabled
        self.handler = handler
    }

    /// The default configuration. Idempotent via the once-token `static let`
    /// initializer side-effect (no lock primitive). Override pieces with the
    /// `.with*` builders.
    public static let `default` = NebulaMetricsConfiguration()

    // MARK: - Fluent builders

    /// Returns a copy with `isEnabled` replaced.
    public func withEnabled(_ isEnabled: Bool) -> NebulaMetricsConfiguration {
        .init(isEnabled: isEnabled, handler: handler)
    }

    /// Returns a copy with the handler replaced.
    public func withHandler(_ handler: @escaping @Sendable (NebulaMetricEvent) -> Void) -> NebulaMetricsConfiguration {
        .init(isEnabled: isEnabled, handler: handler)
    }

    // MARK: - Recording

    /// Records `event` via ``handler`` if ``isEnabled``; otherwise a no-op.
    public func record(_ event: NebulaMetricEvent) {
        guard isEnabled else { return }
        handler(event)
    }

    /// Convenience: builds a ``NebulaMetricEvent`` and records it via
    /// ``record(_:)``. The timestamp defaults to `Date()` at the call site.
    ///
    /// - Parameters:
    ///   - name: The metric name.
    ///   - kind: The metric kind.
    ///   - value: The scalar value (units are kind-dependent).
    ///   - attributes: Per-event typed dimensions. Empty by default.
    public func record(
        _ name: String,
        kind: NebulaMetricKind,
        value: Double,
        attributes: [String: NebulaMetricValue] = [:]
    ) {
        record(NebulaMetricEvent(name: name, kind: kind, value: value, attributes: attributes))
    }
}

//
//  NebulaAnalyticsConfiguration.swift
//  Nebula
//
//  Wave N19b — CloudKit-backed observability suite. The analytics configuration:
//  a `Sendable` value carrying the `isEnabled` gate and a `@Sendable` handler
//  for fan-out, PLUS the `track(_:)` entry point — mirroring how
//  `NebulaMetricsConfiguration` carries `record(_:)` on the config itself.
//  Fluent `.with*` builders mirror the Cosmos sibling's configuration shape
//  WITHOUT SwiftUI `@Entry`/`@Observable`. See
//  vault/03-padroes/nebula-cloudkit-observability.md.
//

import Foundation

/// The Nebula analytics configuration.
///
/// A `Sendable` value (NOT `Equatable` — it stores a `@Sendable` closure, which
/// cannot be compared, mirroring ``NebulaMetricsConfiguration`` and
/// ``NebulaMeasureConfiguration``) describing how analytics events are routed:
/// - ``isEnabled`` gates the secondary ``handler`` fan-out — tracking itself
///   ALWAYS constructs the ``NebulaAnalyticsEvent`` but, when disabled, the
///   handler is not invoked (zero fan-out cost);
/// - ``handler`` is invoked with a ``NebulaAnalyticsEvent`` on every `track()`
///   call, gated on ``isEnabled``. The default `{ _ in }` is capture-free and
///   trivially `Sendable`.
///
/// The contract follows the Cosmos sibling pattern — `Sendable` struct +
/// `@Sendable` handler + fluent `.with*` builders — but with no SwiftUI
/// `@Entry`/`@Observable`: a foundation does not own UI-thread affinity, so
/// configurations are constructed and passed explicitly.
public struct NebulaAnalyticsConfiguration: Sendable {
    /// Whether the secondary ``handler`` fan-out is enabled. Event
    /// construction still runs regardless of this flag; the handler is skipped
    /// when disabled.
    public let isEnabled: Bool
    /// Invoked with a ``NebulaAnalyticsEvent`` on every `track()` call, gated on
    /// ``isEnabled``. The default `{ _ in }` is capture-free and trivially
    /// `Sendable`.
    public let handler: @Sendable (NebulaAnalyticsEvent) -> Void

    /// Creates an analytics configuration.
    ///
    /// - Parameters:
    ///   - isEnabled: Whether the secondary handler fan-out is enabled.
    ///     Defaults to `true`.
    ///   - handler: Invoked with a `NebulaAnalyticsEvent` on every `track()`
    ///     call, gated on `isEnabled`. Defaults to a capture-free no-op.
    public init(
        isEnabled: Bool = true,
        handler: @escaping @Sendable (NebulaAnalyticsEvent) -> Void = { _ in }
    ) {
        self.isEnabled = isEnabled
        self.handler = handler
    }

    /// The default configuration. Idempotent via the once-token `static let`
    /// initializer side-effect (no lock primitive). Override pieces with the
    /// `.with*` builders.
    public static let `default` = NebulaAnalyticsConfiguration()

    // MARK: - Fluent builders

    /// Returns a copy with `isEnabled` replaced.
    public func withEnabled(_ isEnabled: Bool) -> NebulaAnalyticsConfiguration {
        .init(isEnabled: isEnabled, handler: handler)
    }

    /// Returns a copy with the handler replaced.
    public func withHandler(_ handler: @escaping @Sendable (NebulaAnalyticsEvent) -> Void) -> NebulaAnalyticsConfiguration {
        .init(isEnabled: isEnabled, handler: handler)
    }

    // MARK: - Tracking

    /// Tracks `event` via ``handler`` if ``isEnabled``; otherwise a no-op.
    public func track(_ event: NebulaAnalyticsEvent) {
        guard isEnabled else { return }
        handler(event)
    }
}

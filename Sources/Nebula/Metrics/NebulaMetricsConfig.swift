//
//  NebulaMetricsConfig.swift
//  Nebula
//
//  Process-wide current metrics configuration, held in a Mutex (parallel to
//  NebulaLogConfig / NebulaMeasureConfig). Nebula has no SwiftUI Environment,
//  so this accessor gives ergonomics alongside explicit-parameter DI. See
//  vault/03-padroes/nebula-cloudkit-observability.md.
//

import Foundation
import Synchronization

/// Process-wide access to the current ``NebulaMetricsConfiguration``.
///
/// Holds the current config in a `Mutex<NebulaMetricsConfiguration>` from
/// `Synchronization` (`Mutex` requires iOS 18/macOS 15/watchOS 11/tvOS 18/
/// visionOS 2 — all below Nebula's `.v26` floor, so no `@available` gate).
/// `get()`/`set(_:)` are the ergonomic path; explicit
/// ``NebulaMetricsConfiguration`` parameters are the testable path.
///
/// `Mutex<T>` is `~Copyable` and `@_staticExclusiveOnly`, so the backing
/// `current` is declared `let` (never `var`) and stored as a standalone
/// `static let` global.
public enum NebulaMetricsConfig {
    @usableFromInline
    static let current = Mutex<NebulaMetricsConfiguration>(.default)

    /// Returns the current process-wide metrics configuration.
    public static func get() -> NebulaMetricsConfiguration {
        current.withLock { $0 }
    }

    /// Replaces the process-wide metrics configuration.
    public static func set(_ config: NebulaMetricsConfiguration) {
        current.withLock { $0 = config }
    }

    /// Records via the current configuration (convenience over
    /// `NebulaMetricsConfig.get().record(_:)`).
    public static func record(_ event: NebulaMetricEvent) {
        get().record(event)
    }
}

//
//  NebulaAnalyticsConfig.swift
//  Nebula
//
//  Process-wide current analytics configuration, held in a Mutex (parallel to
//  NebulaLogConfig / NebulaMetricsConfig). Nebula has no SwiftUI Environment,
//  so this accessor gives ergonomics alongside explicit-parameter DI. See
//  vault/03-padroes/nebula-cloudkit-observability.md.
//

import Foundation
import Synchronization

/// Process-wide access to the current ``NebulaAnalyticsConfiguration``.
///
/// Holds the current config in a `Mutex<NebulaAnalyticsConfiguration>` from
/// `Synchronization` (`Mutex` requires iOS 18/macOS 15/watchOS 11/tvOS 18/
/// visionOS 2 — all below Nebula's `.v26` floor, so no `@available` gate).
/// `get()`/`set(_:)` are the ergonomic path; explicit
/// ``NebulaAnalyticsConfiguration`` parameters are the testable path.
///
/// `Mutex<T>` is `~Copyable` and `@_staticExclusiveOnly`, so the backing
/// `current` is declared `let` (never `var`) and stored as a standalone
/// `static let` global.
public enum NebulaAnalyticsConfig {
    @usableFromInline
    static let current = Mutex<NebulaAnalyticsConfiguration>(.default)

    /// Returns the current process-wide analytics configuration.
    public static func get() -> NebulaAnalyticsConfiguration {
        current.withLock { $0 }
    }

    /// Replaces the process-wide analytics configuration.
    public static func set(_ config: NebulaAnalyticsConfiguration) {
        current.withLock { $0 = config }
    }

    /// Tracks via the current configuration (convenience over
    /// `NebulaAnalyticsConfig.get().track(_:)`).
    public static func track(_ event: NebulaAnalyticsEvent) {
        get().track(event)
    }
}

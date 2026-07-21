//
//  NebulaNotificationsConfig.swift
//  Nebula
//
//  Wave N15a — App-readiness. Process-wide current notification configuration,
// held in a `Mutex` (parallel to ``NebulaLogConfig`` / ``NebulaErrorConfig``).
// Nebula has no SwiftUI Environment, so this accessor gives ergonomics
// alongside explicit-parameter DI. See vault/03-padroes/nebula-notifications.md.
//

import Foundation
import Synchronization

/// Process-wide access to the current ``NebulaNotificationsConfiguration``.
///
/// Holds the current config in a `Mutex<NebulaNotificationsConfiguration>` from
/// `Synchronization` (`Mutex` requires iOS 18/macOS 15/watchOS 11/tvOS 18/visionOS
/// 2 — all below Nebula's `.v26` floor). `get()` / `set(_:)` are the ergonomic
/// path; an explicit ``NebulaNotificationsConfiguration`` parameter (passed to
/// ``NebulaUNNotificationCenter/init(_:)``) is the testable path.
public enum NebulaNotificationsConfig {
    @usableFromInline
    static let current = Mutex<NebulaNotificationsConfiguration>(.default)

    /// Returns the current process-wide notification configuration.
    public static func get() -> NebulaNotificationsConfiguration {
        current.withLock { $0 }
    }

    /// Replaces the process-wide notification configuration.
    public static func set(_ config: NebulaNotificationsConfiguration) {
        current.withLock { $0 = config }
    }
}
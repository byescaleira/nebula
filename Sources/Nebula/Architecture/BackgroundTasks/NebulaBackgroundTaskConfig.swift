//
//  NebulaBackgroundTaskConfig.swift
//  Nebula
//
//  Wave N15b — App-readiness. Process-wide current background-task configuration,
//  held in a `Mutex` (parallel to ``NebulaLogConfig`` / ``NebulaErrorConfig`` /
//  ``NebulaNotificationsConfig``). Nebula has no SwiftUI Environment, so this
//  accessor gives ergonomics alongside explicit-parameter DI. See
//  vault/03-padroes/nebula-background-tasks.md.
//

import Foundation
import Synchronization

/// Process-wide access to the current ``NebulaBackgroundTaskConfiguration``.
///
/// Holds the current config in a `Mutex<NebulaBackgroundTaskConfiguration>` from
/// `Synchronization` (`Mutex` requires iOS 18/macOS 15/watchOS 11/tvOS 18/visionOS
/// 2 — all below Nebula's `.v26` floor). `get()` / `set(_:)` are the ergonomic
/// path; an explicit ``NebulaBackgroundTaskConfiguration`` parameter (passed to
/// ``NebulaBGTaskScheduler/init(_:)``) is the testable path.
public enum NebulaBackgroundTaskConfig {
    @usableFromInline
    static let current = Mutex<NebulaBackgroundTaskConfiguration>(.default)

    /// Returns the current process-wide background-task configuration.
    public static func get() -> NebulaBackgroundTaskConfiguration {
        current.withLock { $0 }
    }

    /// Replaces the process-wide background-task configuration.
    public static func set(_ config: NebulaBackgroundTaskConfiguration) {
        current.withLock { $0 = config }
    }
}
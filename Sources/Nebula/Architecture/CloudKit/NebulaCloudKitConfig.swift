//
//  NebulaCloudKitConfig.swift
//  Nebula
//
//  Process-wide current CloudKit sync configuration, held in a Mutex (parallel
//  to NebulaLogConfig / NebulaMeasureConfig / NebulaMetricsConfig). Nebula has
//  no SwiftUI Environment, so this accessor gives ergonomics alongside
//  explicit-parameter DI. Deliberately exposes ONLY `get()` / `set(_:)` — no
//  convenience that touches `CKContainer` (which is stateful and would couple
//  this accessor to the CloudKit framework). See
//  vault/03-padroes/nebula-cloudkit-observability.md.
//

import Foundation
import Synchronization

/// Process-wide access to the current ``NebulaCloudKitConfiguration``.
///
/// Holds the current config in a `Mutex<NebulaCloudKitConfiguration>` from
/// `Synchronization` (`Mutex` requires iOS 18/macOS 15/watchOS 11/tvOS 18/
/// visionOS 2 — all below Nebula's `.v26` floor, so no `@available` gate).
/// `get()`/`set(_:)` are the ergonomic path; explicit
/// ``NebulaCloudKitConfiguration`` parameters are the testable path.
///
/// `Mutex<T>` is `~Copyable` and `@_staticExclusiveOnly`, so the backing
/// `current` is declared `let` (never `var`) and stored as a standalone
/// `static let` global.
///
/// - Note: Unlike ``NebulaMetricsConfig`` / ``NebulaLogConfig``, this accessor
///   intentionally offers NO convenience that drives CloudKit. `CKContainer`
///   is stateful (it lazily resolves the iCloud account and databases), and
///   surfacing a `sync()` convenience here would couple a process-wide
///   accessor to the CloudKit framework and to network I/O. Consumers
///   construct a ``NebulaCloudKitSyncEngine`` explicitly with the resolved
///   configuration.
public enum NebulaCloudKitConfig {
    @usableFromInline
    static let current = Mutex<NebulaCloudKitConfiguration>(.default)

    /// Returns the current process-wide CloudKit sync configuration.
    public static func get() -> NebulaCloudKitConfiguration {
        current.withLock { $0 }
    }

    /// Replaces the process-wide CloudKit sync configuration.
    public static func set(_ config: NebulaCloudKitConfiguration) {
        current.withLock { $0 = config }
    }
}

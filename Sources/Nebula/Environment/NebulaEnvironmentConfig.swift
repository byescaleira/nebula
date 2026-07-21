//
//  NebulaEnvironmentConfig.swift
//  Nebula
//
//  Process-wide current environment configuration, held in a `Mutex` (parallel
//  to `NebulaLogConfig` / `NebulaErrorConfig` / `NebulaStandardsConfig` /
//  `NebulaMeasureConfig`). Nebula has no SwiftUI `Environment`, so this accessor
//  gives ergonomics alongside explicit-parameter DI (DECISIONS.md row 27 — the
//  two-path rule). The value carries no `@Sendable` handler, but the `Mutex`
//  shape is identical to the standards/measure accessors. See
//  vault/03-padroes/nebula-environment.md.
//

import Foundation
import Synchronization

/// Process-wide access to the current ``NebulaEnvironmentConfiguration``.
///
/// Holds the current config in a `Mutex<NebulaEnvironmentConfiguration>` from
/// `Synchronization` (`Mutex` requires iOS 18 / macOS 15 / watchOS 11 / tvOS 18
/// / visionOS 2 — all below Nebula's `.v26` floor, so no `@available` gate).
/// `get()` / `set(_:)` are the ergonomic path; passing an explicit
/// ``NebulaEnvironmentConfiguration`` parameter is the testable path.
///
/// `Mutex` is `~Copyable` and `@_staticExclusiveOnly`, so the backing property
/// is a `let` (never `var`) — see `CLAUDE.md` (Concurrency).
public enum NebulaEnvironmentConfig {
    @usableFromInline
    static let current = Mutex<NebulaEnvironmentConfiguration>(.default)

    /// Returns the current process-wide environment configuration.
    public static func get() -> NebulaEnvironmentConfiguration {
        current.withLock { $0 }
    }

    /// Replaces the process-wide environment configuration.
    public static func set(_ config: NebulaEnvironmentConfiguration) {
        current.withLock { $0 = config }
    }
}
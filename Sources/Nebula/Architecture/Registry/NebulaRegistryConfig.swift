//
//  NebulaRegistryConfig.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. Process-wide registry access, held in a
//  `Mutex` (no NSLock/DispatchQueue/nonisolated(unsafe)). Nebula has no SwiftUI
//  Environment, so the Cosmos injection path is unavailable; this accessor gives
//  ergonomics alongside explicit-parameter DI (decision #5 — both). Mirrors
//  ``NebulaErrorConfig``. See vault/03-padroes/nebula-registry-di.md.
//

import Foundation
import Synchronization

/// Process-wide access to the current ``NebulaRegistryConfiguration``.
///
/// Holds the current config in a `Mutex<NebulaRegistryConfiguration>` from
/// `Synchronization` (below Nebula's `.v26` floor). `get()`/`set(_:)` are the
/// ergonomic path; explicit ``NebulaRegistry`` parameters are the testable path.
/// Both are supported.
public enum NebulaRegistryConfig {
    @usableFromInline
    static let current = Mutex<NebulaRegistryConfiguration>(.default)

    /// Returns the current process-wide registry configuration.
    public static func get() -> NebulaRegistryConfiguration {
        current.withLock { $0 }
    }

    /// Replaces the process-wide registry configuration.
    public static func set(_ config: NebulaRegistryConfiguration) {
        current.withLock { $0 = config }
    }

    /// Resolves `key` to a typed instance via the current configuration's bound
    /// factory, or `nil` when unbound or not castable to `T`.
    public static func resolve<T>(_ key: NebulaRegistryKey, as type: T.Type = T.self) -> T? {
        current.withLock { $0.make(key) as? T }
    }
}
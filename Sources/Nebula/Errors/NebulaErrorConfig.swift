//
//  NebulaErrorConfig.swift
//  Nebula
//
//  Process-wide current error-reporting configuration, held in a Mutex (no
//  NSLock/DispatchQueue/nonisolated(unsafe)). Nebula has no SwiftUI Environment,
//  so the Cosmos injection path is unavailable; this accessor gives ergonomics
//  alongside explicit-parameter DI. See vault/01-fundamentos/nebula-errors.md.
//

import Foundation
import Synchronization

/// Process-wide access to the current ``NebulaErrorConfiguration``.
///
/// Holds the current config in a `Mutex<NebulaErrorConfiguration>` from
/// `Synchronization` (`Mutex` requires iOS 18/macOS 15/watchOS 11/tvOS 18/visionOS
/// 2 — all below Nebula's `.v26` floor). `get()`/`set(_:)` are the ergonomic
/// path; explicit ``NebulaErrorConfiguration`` parameters are the testable
/// path. Both are supported.
public enum NebulaErrorConfig {
    @usableFromInline
    static let current = Mutex<NebulaErrorConfiguration>(.default)

    /// Returns the current process-wide error configuration.
    public static func get() -> NebulaErrorConfiguration {
        current.withLock { $0 }
    }

    /// Replaces the process-wide error configuration.
    public static func set(_ config: NebulaErrorConfiguration) {
        current.withLock { $0 = config }
    }

    /// Reports `error` through the current configuration (convenience over
    /// `NebulaErrorConfig.get().report(_:)`).
    public static func report(_ error: NebulaError) {
        get().report(error)
    }
}
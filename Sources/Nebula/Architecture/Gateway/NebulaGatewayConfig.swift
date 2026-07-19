//
//  NebulaGatewayConfig.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. Process-wide current gateway
//  configuration, held in a Mutex (parallel to NebulaErrorConfig /
//  NebulaLogConfig / NebulaMeasureConfig / NebulaStandardsConfig). Nebula has no
//  SwiftUI Environment, so this accessor gives ergonomics alongside
//  explicit-parameter DI. See vault/03-padroes/nebula-repository.md.
//

import Foundation
import Synchronization

/// Process-wide access to the current ``NebulaGatewayConfiguration``.
///
/// Holds the current config in a `Mutex<NebulaGatewayConfiguration>` from
/// `Synchronization` (`Mutex` requires iOS 18/macOS 15/watchOS 11/tvOS 18/
/// visionOS 2 — all below Nebula's `.v26` floor, so no `@available` gate).
/// `get()`/`set(_:)` are the ergonomic path; explicit
/// ``NebulaGatewayConfiguration`` parameters are the testable path.
///
/// `Mutex<T>` is `~Copyable` and `@_staticExclusiveOnly`, so the backing
/// `current` is declared `let` (never `var`) and stored as a standalone
/// `static let` global.
public enum NebulaGatewayConfig {
    @usableFromInline
    static let current = Mutex<NebulaGatewayConfiguration>(.default)

    /// Returns the current process-wide gateway configuration.
    public static func get() -> NebulaGatewayConfiguration {
        current.withLock { $0 }
    }

    /// Replaces the process-wide gateway configuration.
    public static func set(_ config: NebulaGatewayConfiguration) {
        current.withLock { $0 = config }
    }
}
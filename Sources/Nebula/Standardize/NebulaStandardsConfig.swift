//
//  NebulaStandardsConfig.swift
//  Nebula
//
//  Process-wide current formatting-standards configuration, held in a `Mutex`
//  (parallel to `NebulaLogConfig` / `NebulaErrorConfig`). Nebula has no SwiftUI
//  `Environment`, so this accessor gives ergonomics alongside explicit-parameter
//  DI. Unlike the log/error config accessors, the standards value carries no
//  `@Sendable` handler — formatting is stateless — but the `Mutex` shape is
//  identical. See vault/01-fundamentos/nebula-standardize-measure.md.
//

import Foundation
import Synchronization

/// Process-wide access to the current ``NebulaStandards``.
///
/// Holds the current config in a `Mutex<NebulaStandards>` from
/// `Synchronization` (`Mutex` requires iOS 18 / macOS 15 / watchOS 11 / tvOS 18
/// / visionOS 2 — all below Nebula's `.v26` floor, so no `@available` gate).
/// `get()` / `set(_:)` are the ergonomic path; passing an explicit
/// ``NebulaStandards`` parameter is the testable path.
///
/// `Mutex` is `~Copyable` and `@_staticExclusiveOnly`, so the backing property
/// is a `let` (never `var`) — see `CLAUDE.md` (Concurrency).
public enum NebulaStandardsConfig {
    @usableFromInline
    static let current = Mutex<NebulaStandards>(.default)

    /// Returns the current process-wide formatting-standards configuration.
    public static func get() -> NebulaStandards {
        current.withLock { $0 }
    }

    /// Replaces the process-wide formatting-standards configuration.
    public static func set(_ config: NebulaStandards) {
        current.withLock { $0 = config }
    }
}
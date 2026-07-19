//
//  NebulaLogConfig.swift
//  Nebula
//
//  Process-wide current logging configuration, held in a Mutex (parallel to
//  NebulaErrorConfig). Nebula has no SwiftUI Environment, so this accessor
//  gives ergonomics alongside explicit-parameter DI. See
//  vault/01-fundamentos/nebula-logging.md.
//

import Foundation
import Synchronization

/// Process-wide access to the current ``NebulaLogConfiguration``.
///
/// Holds the current config in a `Mutex<NebulaLogConfiguration>` from
/// `Synchronization` (`Mutex` requires iOS 18/macOS 15/watchOS 11/tvOS 18/visionOS
/// 2 — all below Nebula's `.v26` floor). `get()`/`set(_:)` are the ergonomic
/// path; explicit ``NebulaLogConfiguration`` parameters are the testable path.
public enum NebulaLogConfig {
    @usableFromInline
    static let current = Mutex<NebulaLogConfiguration>(.default)

    /// Returns the current process-wide logging configuration.
    public static func get() -> NebulaLogConfiguration {
        current.withLock { $0 }
    }

    /// Replaces the process-wide logging configuration.
    public static func set(_ config: NebulaLogConfiguration) {
        current.withLock { $0 = config }
    }

    /// Emits via the current configuration (convenience over
    /// `NebulaLogConfig.get().log(_:_:)`).
    public static func log(_ level: NebulaLogLevel, _ message: String) {
        get().log(level, message)
    }
}
//
//  NebulaMeasureConfig.swift
//  Nebula
//
//  Process-wide current measure configuration, held in a Mutex (parallel to
//  NebulaLogConfig / NebulaErrorConfig). Nebula has no SwiftUI Environment, so
//  this accessor gives ergonomics alongside explicit-parameter DI. See
//  vault/01-fundamentos/nebula-standardize-measure.md.
//

import Foundation
import Synchronization

/// Process-wide access to the current ``NebulaMeasureConfiguration``.
///
/// Holds the current config in a `Mutex<NebulaMeasureConfiguration>` from
/// `Synchronization` (`Mutex` requires iOS 18/macOS 15/watchOS 11/tvOS 18/
/// visionOS 2 — all below Nebula's `.v26` floor, so no `@available` gate).
/// `get()`/`set(_:)` are the ergonomic path; explicit
/// ``NebulaMeasureConfiguration`` parameters are the testable path.
///
/// `Mutex<T>` is `~Copyable` and `@_staticExclusiveOnly`, so the backing
/// `current` is declared `let` (never `var`) and stored as a standalone
/// `static let` global.
public enum NebulaMeasureConfig {
    @usableFromInline
    static let current = Mutex<NebulaMeasureConfiguration>(.default)

    /// Returns the current process-wide measure configuration.
    public static func get() -> NebulaMeasureConfiguration {
        current.withLock { $0 }
    }

    /// Replaces the process-wide measure configuration.
    public static func set(_ config: NebulaMeasureConfiguration) {
        current.withLock { $0 = config }
    }
}
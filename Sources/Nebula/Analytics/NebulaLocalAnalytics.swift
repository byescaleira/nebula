//
//  NebulaLocalAnalytics.swift
//  Nebula
//
//  Wave N19b — CloudKit-backed observability suite. An in-memory façade for
//  tests and previews: a `final class` conforming to ``NebulaAnalytics`` that
//  accumulates ``NebulaAnalyticsEvent``s in a `Mutex<[NebulaAnalyticsEvent]>`.
//  `Sendable` is derived (the `~Copyable` `Mutex` is absorbed behind a
//  copyable, `Sendable` reference — the `NebulaHTTPServer.OnceFlag` precedent;
//  NO `@unchecked`). See vault/03-padroes/nebula-cloudkit-observability.md.
//

import Foundation
import Synchronization

/// An in-memory ``NebulaAnalytics`` conformer for tests and previews.
///
/// A `final class` backed by a `Mutex<[NebulaAnalyticsEvent]>` (Swift 6
/// `Synchronization`; `Mutex` requires iOS 18/macOS 15/watchOS 11/tvOS 18/
/// visionOS 2 — all below Nebula's `.v26` floor, so no `@available` gate). The
/// class is `final` and all stored properties are `Sendable`, so `Sendable` is
/// derived — no `@unchecked` conformance is authored.
///
/// - Important: This is intended for **tests and previews only**. It is `public`
///   so consumers can capture events without a separate test-support module
///   (the single-target rule); shipping it in a release build is fine but it
///   is not a production analytics backend.
public final class NebulaLocalAnalytics: NebulaAnalytics {
    /// The captured-event buffer. `Mutex` is `~Copyable` /
    /// `@_staticExclusiveOnly`, so declared `let` and held by value inside this
    /// copyable reference.
    @usableFromInline
    let buffer: Mutex<[NebulaAnalyticsEvent]>

    /// Creates an empty sink.
    public init() {
        self.buffer = Mutex([])
    }

    /// Tracks (appends) an analytics event to the buffer.
    ///
    /// - Parameter event: The analytics event to capture.
    public func track(_ event: NebulaAnalyticsEvent) {
        buffer.withLock { events in events.append(event) }
    }

    /// Returns a snapshot copy of the captured events, in insertion order.
    public var events: [NebulaAnalyticsEvent] {
        buffer.withLock { events in events }
    }

    /// Removes all captured events.
    public func removeAll() {
        buffer.withLock { events in events.removeAll() }
    }
}

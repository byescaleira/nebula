//
//  NebulaMemoryLogHandler.swift
//  Nebula
//
//  In-memory ring-buffer sink for tests and preview. The only @unchecked
//  Sendable type in the logging module: a final class guarding a ~Copyable
//  Mutex<[NebulaLogEvent]> ring buffer. Per ADR, this lives in the main target
//  (not a separate test-support module) and is documented as test/preview-only.
//  See vault/01-fundamentos/nebula-logging.md.
//

import Foundation
import Synchronization

/// An in-memory ring buffer of ``NebulaLogEvent``s for tests and previews.
///
/// A `final class @unchecked Sendable` backed by a `Mutex<[NebulaLogEvent]>`
/// ring buffer (Swift 6 `Synchronization`; `Mutex` requires iOS 18/macOS
/// 15/watchOS 11/tvOS 18/visionOS 2 — all below Nebula's `.v26` floor, so no
/// `@available` gate). The `@unchecked` conformance is justified by the lock:
/// `Mutex` guarantees exclusive access to the buffer.
///
/// - Important: This is intended for **tests and previews only**. It is
///   `public` so consumers can capture events without a separate test-support
///   module (the single-target rule); shipping it in a release build is fine
///   but it is not a production log backend.
///
/// Capture events by plugging its ``handler`` into a
/// ``NebulaLogConfiguration``:
///
/// ```swift
/// let sink = NebulaMemoryLogHandler()
/// let config = NebulaLogConfiguration.default
///     .withSubsystem("com.acme.app")
///     .withHandler(sink.handler)
/// config.log(.error, "boom")
/// let events = sink.snapshot()   // [NebulaLogEvent(...)]
/// ```
public final class NebulaMemoryLogHandler: @unchecked Sendable {
    // @unchecked because: a ~Copyable `Mutex` guards the mutable buffer; the
    // lock guarantees exclusive access, so the class is soundly Sendable. The
    // `Mutex` is held as `let` (Mutex is @_staticExclusiveOnly).
    @usableFromInline
    let buffer: Mutex<[NebulaLogEvent]>
    private let capacity: Int

    /// Creates a sink holding at most `capacity` most-recent events.
    public init(capacity: Int = 1024) {
        precondition(capacity > 0, "NebulaMemoryLogHandler capacity must be > 0")
        self.capacity = capacity
        self.buffer = Mutex([])
    }

    /// A `@Sendable` closure that appends an event to the ring buffer. Plug
    /// this into ``NebulaLogConfiguration/withHandler(_:)``.
    ///
    /// Computed (not stored) so it can capture `self` — a `Sendable` class
    /// reference — without copying the `~Copyable` `Mutex` across the closure
    /// boundary. Each access yields a fresh closure that shares this sink.
    public var handler: @Sendable (NebulaLogEvent) -> Void {
        { [self] event in self.append(event) }
    }

    private func append(_ event: NebulaLogEvent) {
        buffer.withLock { events in
            events.append(event)
            let overflow = events.count - capacity
            if overflow > 0 { events.removeFirst(overflow) }
        }
    }

    /// Returns a copy of the buffered events, oldest-first.
    public func snapshot() -> [NebulaLogEvent] {
        buffer.withLock { events in events }
    }

    /// Removes all buffered events.
    public func clear() {
        buffer.withLock { events in events.removeAll() }
    }

    /// The number of events currently buffered.
    public var count: Int {
        buffer.withLock { events in events.count }
    }
}
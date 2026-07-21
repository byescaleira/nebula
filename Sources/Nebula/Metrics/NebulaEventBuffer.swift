//
//  NebulaEventBuffer.swift
//  Nebula
//
//  Wave N19a — CloudKit-backed observability suite. A generic batching helper:
//  a `final class` (derives `Sendable` — the `~Copyable` `Mutex` is absorbed
//  behind a copyable, `Sendable` reference, mirroring the
//  `NebulaHTTPServer.OnceFlag` precedent; NO `@unchecked`) that accumulates
//  `Sendable & Equatable` events and flushes a batch to a `@Sendable` handler
//  when `pending.count >= batchSize` (or on demand via ``flush()``). Shared by
//  the metrics / analytics / performance-sink slices. See
//  vault/03-padroes/nebula-cloudkit-observability.md.
//

import Foundation
import Synchronization

/// A generic in-memory batch buffer for `Sendable & Equatable` events.
///
/// A `final class` that accumulates events in a `Mutex<[Event]>` and invokes a
/// `@Sendable` handler with a batch when the pending count reaches `batchSize`
/// (on ``append(_:)``) or when ``flush()`` is called. The `~Copyable` `Mutex` is
/// absorbed behind a copyable, `Sendable` reference (the
/// `NebulaHTTPServer.OnceFlag` / `NebulaDefaults` precedent) — no `@unchecked`
/// conformance is authored: the class is `final`, all stored properties are
/// `Sendable`, so `Sendable` is derived.
///
/// The handler is invoked **outside** the lock to avoid reentrancy: a batch is
/// drained under the lock (copied out, pending reset to `[]`), then handed to
/// the handler after the lock releases.
///
/// - Note: This is a building block for batching sinks (metrics fan-out,
///   analytics upload, performance-sink flush). It does not retry, persist, or
///   bound latency — callers that need those compose this with their own
///   timer/retry policy.
public final class NebulaEventBuffer<Event: Sendable & Equatable>: Sendable {
    /// The pending-event buffer. `Mutex` is `~Copyable` / `@_staticExclusiveOnly`,
    /// so declared `let` and held by value inside this copyable reference.
    @usableFromInline
    let buffer: Mutex<[Event]>
    /// The flush threshold. When `pending.count >= batchSize`, ``append(_:)``
    /// drains a batch to ``handler``.
    public let batchSize: Int
    /// Invoked with a flushed batch (outside the lock). `@Sendable`.
    public let handler: @Sendable ([Event]) -> Void

    /// Creates a batch buffer.
    ///
    /// - Parameters:
    ///   - batchSize: The flush threshold. Must be `> 0`. Defaults to `50`.
    ///   - handler: Invoked with a batch when `pending.count >= batchSize` (on
    ///     ``append(_:)``) or on ``flush()``. Defaults to a capture-free no-op.
    public init(
        batchSize: Int = 50,
        handler: @escaping @Sendable ([Event]) -> Void = { _ in }
    ) {
        precondition(batchSize > 0, "NebulaEventBuffer batchSize must be > 0")
        self.buffer = Mutex([])
        self.batchSize = batchSize
        self.handler = handler
    }

    /// Appends `event` to the pending buffer. If the pending count reaches
    /// ``batchSize``, drains the buffer to ``handler`` (outside the lock).
    public func append(_ event: Event) {
        var batch: [Event] = []
        buffer.withLock { pending in
            pending.append(event)
            if pending.count >= batchSize {
                batch = pending
                pending = []
            }
        }
        if !batch.isEmpty { handler(batch) }
    }

    /// Flushes the pending buffer to ``handler`` regardless of size. A no-op
    /// (the handler is not called) when the buffer is empty.
    public func flush() {
        var batch: [Event] = []
        buffer.withLock { pending in
            batch = pending
            pending = []
        }
        if !batch.isEmpty { handler(batch) }
    }
}

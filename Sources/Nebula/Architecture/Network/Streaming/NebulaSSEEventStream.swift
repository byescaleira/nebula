//
//  NebulaSSEEventStream.swift
//  Nebula
//
//  Wave N17b — Streaming. Server-Sent Events over `URLSession.bytes(for:)`:
//  a pure WHATWG-spec parser (``NebulaSSEParser``) feeds an
//  ``NebulaSSEEvent``-yielding ``AsyncThrowingStream`` (the CLAUDE.md-mandated
//  concrete return type — `some AsyncSequence` is illegal in a protocol
//  requirement, and this stream is returned from a `static func`). Includes
//  spec-compliant auto-reconnect with `Last-Event-ID`.
//
//  IMPORTANT: the raw `URLSession.AsyncBytes` byte stream is iterated directly
//  (NOT `.lines`) — `AsyncLineSequence` skips empty lines, but SSE dispatches
//  on the blank line, so `.lines` would drop every dispatch boundary. Lines
//  are formed by accumulating bytes until `\n` (the parser strips a trailing
//  `\r` defensively).
//
//  The reconnect loop is **custom** (NOT ``NebulaRetry/withPolicy``): the
//  request mutates per attempt (the `Last-Event-ID` header advances with the
//  cursor), and `withPolicy`'s `operation` is a nullary closure that cannot
//  mutate the request between attempts. The loop mirrors `withPolicy`'s
//  cancellation contract — cancellation is honored immediately and **never
//  retried** (the loop finishes on a `CancellationError` / `URLError(.cancelled)`).
//  Note: on the *consumer* side, an `AsyncThrowingStream` iteration ends
//  normally on consumer cancellation (`Iterator.next()` returns `nil`; it does
//  not throw) — the consumer never observes the internal `finish(throwing:)`.
//  The internal `finish(throwing: CancellationError())` exists to tear the
//  internal `bytes(for:)` task down cleanly via `onTermination → loop.cancel()`.
//  See vault/03-padroes/nebula-streaming.md.
//
//  All symbols are below the `.v26` floor on every platform
//  (`URLSession.bytes(for:)` is macOS 12 / iOS 15 / watchOS 8 / tvOS 15 /
//  visionOS 1.0+; `AsyncThrowingStream` is macOS 10.15 / iOS 13 / watchOS 6 /
//  tvOS 13) — **no `@available` gate** anywhere here. `import Foundation` only.
//

import Foundation

/// A parsed Server-Sent Event (per the WHATWG Server-Sent Events spec).
///
/// Dispatched by ``NebulaSSEEventStream`` on each blank line in the stream
/// (when the `data` buffer is non-empty). `Sendable`, `Equatable`, and
/// `Hashable` are derived from the value-type fields.
public struct NebulaSSEEvent: Sendable, Equatable, Hashable {

    /// The last event ID (`id:` field), carried across dispatches and used as
    /// the `Last-Event-ID` request header on reconnect. `nil` until an `id:`
    /// field is seen.
    public let id: String?

    /// The event type (`event:` field, or `"message"` when unset).
    public let event: String

    /// The accumulated `data:` payload (multi-line `data:` joined with `\n`,
    /// trailing newline stripped per WHATWG).
    public let data: String

    /// The reconnection delay in milliseconds (`retry:` field), or `nil` when
    /// unset. Carried across dispatches. Nebula does not auto-apply this — the
    /// consumer may read it to drive its own backoff.
    public let retry: Int?

    /// Creates an event.
    public init(id: String?, event: String, data: String, retry: Int?) {
        self.id = id
        self.event = event
        self.data = data
        self.retry = retry
    }
}

/// A pure WHATWG Server-Sent Events parser state machine (the testable seam).
///
/// Feed it lines (from `URLSession.AsyncBytes.lines` or canned `[String]` in
/// tests); it returns a fully-formed ``NebulaSSEEvent`` on a blank-line
/// dispatch (when the `data` buffer is non-empty), `nil` otherwise. The parser
/// holds no I/O and no `@Sendable` closure — it is pure, so it is unit-tested
/// directly without a `URLSession`.
///
/// WHATWG rules implemented:
/// - A line starting with `:` is a comment (ignored).
/// - `field: value` splits on the first colon; one leading space after the
///   colon is stripped (per spec).
/// - A line without a colon is a field with an empty value.
/// - `event` sets the event type; `data` appends `value + "\n"`; `id` sets the
///   last event ID (rejected if the value contains U+0000 NULL, per spec);
///   `retry` parses a non-negative integer (lossy: non-int values ignored).
/// - Unknown fields are ignored.
/// - A blank line dispatches (when `data` is non-empty), resetting the `data`
///   and `event` buffers while **preserving** `lastEventID` and `retry`
///   across dispatches (per spec).
///
/// A trailing `\r` is defensively stripped (``URLSession/AsyncBytes```
/// `.lines` already strips line terminators; this is a safety net).
internal struct NebulaSSEParser {

    /// The last event ID (`id:` field), carried across dispatches.
    internal private(set) var lastEventID: String?

    /// The reconnection delay in milliseconds (`retry:` field), carried across
    /// dispatches.
    internal private(set) var retry: Int?

    private var dataBuffer: String = ""
    private var eventBuffer: String = ""

    /// Creates a parser.
    init(retry: Int? = nil) {
        self.retry = retry
    }

    /// Feeds a line; returns a dispatched event on a blank line (when the data
    /// buffer is non-empty), `nil` otherwise.
    @discardableResult
    mutating func feed(_ line: String) -> NebulaSSEEvent? {
        var line = line
        if line.hasSuffix("\r") { line.removeLast() }

        if line.isEmpty {
            return dispatch()
        }
        if line.hasPrefix(":") {
            return nil
        }

        let field: String
        let value: String
        if let colon = line.firstIndex(of: ":") {
            field = String(line[..<colon])
            var v = String(line[line.index(after: colon)...])
            if v.hasPrefix(" ") { v.removeFirst() }
            value = v
        } else {
            field = line
            value = ""
        }

        switch field {
        case "event":
            eventBuffer = value
        case "data":
            dataBuffer += value
            dataBuffer += "\n"
        case "id":
            if !value.contains("\u{0000}") {
                lastEventID = value
            }
        case "retry":
            if let ms = Int(value), ms >= 0 {
                retry = ms
            }
        default:
            break
        }
        return nil
    }

    /// Dispatches on a blank line (when `data` is non-empty), resetting the
    /// `data`/`event` buffers while preserving `lastEventID`/`retry`.
    private mutating func dispatch() -> NebulaSSEEvent? {
        guard !dataBuffer.isEmpty else {
            // No data — reset buffers (the defer below) but do not dispatch.
            // A deliberate, documented deviation from the strict spec (which
            // dispatches an empty-data event): pure-control blank lines (only
            // `id:`/`event:`/`retry:` set, no `data:`) do not yield spurious
            // empty events. Heartbeats are `:` comments, not blank lines.
            dataBuffer = ""
            eventBuffer = ""
            return nil
        }
        var data = dataBuffer
        if data.hasSuffix("\n") { data.removeLast() }
        let type = eventBuffer.isEmpty ? "message" : eventBuffer
        let event = NebulaSSEEvent(id: lastEventID, event: type, data: data, retry: retry)
        dataBuffer = ""
        eventBuffer = ""
        return event
    }
}

/// Configuration for ``NebulaSSEEventStream``.
///
/// `Sendable` but **NOT `Equatable`** — the `sleeper` is a `@Sendable` closure
/// (mirroring ``NebulaLogConfiguration``'s not-`Equatable` handler flavor). This
/// is a **per-call** value (passed to ``NebulaSSEEventStream/events(for:session:configuration:)``),
/// not a process-wide accessor — there is no `Mutex<NebulaSSEConfiguration>`
/// accessor (unlike the process-wide logging/measurement/error configs).
public struct NebulaSSEConfiguration: Sendable {

    /// Whether to reconnect after a clean stream end or a recoverable error.
    public let reconnect: Bool

    /// The maximum number of reconnect attempts before giving up.
    public let maxReconnectAttempts: Int

    /// The delay between reconnect attempts.
    public let reconnectDelay: Duration

    /// The sleeper — injectable for tests (default ``NebulaRetry/defaultSleep``).
    public let sleeper: @Sendable (Duration) async throws -> Void

    /// Creates the configuration.
    public init(
        reconnect: Bool = true,
        maxReconnectAttempts: Int = 5,
        reconnectDelay: Duration = .seconds(3),
        sleeper: @Sendable @escaping (Duration) async throws -> Void = NebulaRetry.defaultSleep
    ) {
        self.reconnect = reconnect
        self.maxReconnectAttempts = maxReconnectAttempts
        self.reconnectDelay = reconnectDelay
        self.sleeper = sleeper
    }

    /// The default configuration.
    public static let `default`: NebulaSSEConfiguration = .init()

    /// Returns a copy with `reconnect` replaced.
    public func withReconnect(_ reconnect: Bool) -> NebulaSSEConfiguration {
        .init(reconnect: reconnect, maxReconnectAttempts: maxReconnectAttempts,
              reconnectDelay: reconnectDelay, sleeper: sleeper)
    }

    /// Returns a copy with `maxReconnectAttempts` replaced.
    public func withMaxReconnectAttempts(_ maxReconnectAttempts: Int) -> NebulaSSEConfiguration {
        .init(reconnect: reconnect, maxReconnectAttempts: maxReconnectAttempts,
              reconnectDelay: reconnectDelay, sleeper: sleeper)
    }

    /// Returns a copy with `reconnectDelay` replaced.
    public func withReconnectDelay(_ reconnectDelay: Duration) -> NebulaSSEConfiguration {
        .init(reconnect: reconnect, maxReconnectAttempts: maxReconnectAttempts,
              reconnectDelay: reconnectDelay, sleeper: sleeper)
    }

    /// Returns a copy with `sleeper` replaced.
    public func withSleeper(_ sleeper: @Sendable @escaping (Duration) async throws -> Void) -> NebulaSSEConfiguration {
        .init(reconnect: reconnect, maxReconnectAttempts: maxReconnectAttempts,
              reconnectDelay: reconnectDelay, sleeper: sleeper)
    }
}

/// Server-Sent Events streaming over `URLSession.bytes(for:)`.
///
/// `events(for:session:configuration:)` returns an
/// `AsyncThrowingStream<NebulaSSEEvent, any Error>` — the CLAUDE.md-mandated
/// concrete return type. Internally it parses the raw `AsyncBytes` byte stream
/// with ``NebulaSSEParser`` and yields dispatched events; on a clean stream end
/// or a recoverable error it reconnects (when configured), sending the
/// cursor's `Last-Event-ID` header. Cancellation is honored immediately and
/// never retried (mirroring ``NebulaRetry``). When the consumer stops
/// iterating (cancels its `Task` or the stream finishes), `onTermination`
/// cancels the internal loop so the `bytes(for:)` task is torn down — the
/// consumer's `for try await` ends normally on cancellation (an
/// `AsyncThrowingStream` does not throw `CancellationError` to its consumer).
public enum NebulaSSEEventStream {

    /// Yields ``NebulaSSEEvent``s from the SSE stream at `request`.
    ///
    /// - Parameters:
    ///   - request: the SSE endpoint request.
    ///   - session: the `URLSession` (default `.shared`; pass a pinned session
    ///     from ``NebulaHTTPSession/pinned(by:configuration:logger:)`` for
    ///     SSL/TLS pinning — pinning rides the session's delegate).
    ///   - configuration: the reconnect behavior + sleeper (default
    ///     ``NebulaSSEConfiguration/default``).
    /// - Returns: an `AsyncThrowingStream<NebulaSSEEvent, any Error>` — the
    ///   concrete return type (per CLAUDE.md).
    public static func events(
        for request: URLRequest,
        session: URLSession = .shared,
        configuration: NebulaSSEConfiguration = .default
    ) -> AsyncThrowingStream<NebulaSSEEvent, any Error> {
        AsyncThrowingStream { continuation in
            // Tie the internal loop's lifetime to the consumer's: when the
            // consumer stops iterating (cancel or finish), cancel the loop so
            // the `URLSession.bytes(for:)` task does not leak.
            let loop = Task {
                var attemptsLeft = configuration.maxReconnectAttempts
                var parser = NebulaSSEParser()
                while true {
                    do {
                        try Task.checkCancellation()
                        let cursorRequest = applyLastEventID(to: request, from: parser.lastEventID)
                        let (bytes, _) = try await session.bytes(for: cursorRequest)
                        // Iterate the raw byte stream and form lines manually —
                        // `AsyncBytes.lines` (AsyncLineSequence) skips empty lines,
                        // but SSE dispatches on the blank line, so `.lines` is
                        // unsuitable. A `\n` ends a line (a `\r\n` pair is handled
                        // by the parser's defensive `\r` strip); an empty buffer
                        // at `\n` is the blank line that triggers dispatch.
                        var lineBuffer = Data()
                        for try await byte in bytes {
                            if byte == 0x0A {
                                let line = String(data: lineBuffer, encoding: .utf8) ?? ""
                                if let event = parser.feed(line) {
                                    continuation.yield(event)
                                }
                                lineBuffer.removeAll(keepingCapacity: true)
                            } else {
                                lineBuffer.append(byte)
                            }
                        }
                        // Flush a trailing partial line (no terminating `\n`).
                        if !lineBuffer.isEmpty {
                            let line = String(data: lineBuffer, encoding: .utf8) ?? ""
                            if let event = parser.feed(line) {
                                continuation.yield(event)
                            }
                        }
                        // Clean stream end.
                        guard configuration.reconnect, attemptsLeft > 0 else {
                            continuation.finish()
                            return
                        }
                        attemptsLeft -= 1
                        try Task.checkCancellation()
                        try await configuration.sleeper(configuration.reconnectDelay)
                    } catch is CancellationError {
                        continuation.finish(throwing: CancellationError())
                        return
                    } catch let error as URLError where error.code == .cancelled {
                        // Cancellation surfaces as URLError(.cancelled) too.
                        continuation.finish(throwing: CancellationError())
                        return
                    } catch {
                        guard configuration.reconnect, attemptsLeft > 0 else {
                            let box = NebulaError.Box(NebulaError(error: error))
                            continuation.finish(throwing: NebulaSSEError.connectFailed(
                                "SSE stream failed: \(error.localizedDescription)",
                                underlying: box))
                            return
                        }
                        attemptsLeft -= 1
                        do {
                            try Task.checkCancellation()
                            try await configuration.sleeper(configuration.reconnectDelay)
                        } catch {
                            continuation.finish(throwing: CancellationError())
                            return
                        }
                    }
                }
            }
            continuation.onTermination = { @Sendable _ in loop.cancel() }
        }
    }

    /// Returns a copy of `request` with the `Last-Event-ID` header set to
    /// `lastEventID` (only when non-`nil`); otherwise the original request.
    private static func applyLastEventID(to request: URLRequest, from lastEventID: String?) -> URLRequest {
        guard let lastEventID else { return request }
        var req = request
        req.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID")
        return req
    }
}
//
//  NebulaLogEvent.swift
//  Nebula
//
//  A Sendable value capturing a log event for the handler fan-out path. See
//  vault/01-fundamentos/nebula-logging.md ("Two emission paths").
//

import Foundation

/// A `Sendable` snapshot of a log event, used by the secondary handler fan-out
/// path on ``NebulaLogConfiguration``.
///
/// The primary emission path forwards an `OSLogMessage` straight to
/// `os.Logger`, preserving per-argument privacy redaction in Console.app — that
/// path carries no value Nebula can hand to a handler. This struct is the
/// redaction-losing, dynamic-`String` alternative so in-memory sinks / test
/// handlers can capture events as plain values:
///
/// ```swift
/// let sink = NebulaMemoryLogHandler()
/// let config = NebulaLogConfiguration.default.withHandler(sink.handler)
/// config.log(.error, "failed")   // → os.Logger AND sink.handler(NebulaLogEvent(...))
/// ```
///
/// - Important: The ``message`` is the interpolated `String` (already
///   privacy-redacted to `.public` on this path). Callers wanting per-argument
///   redaction should use ``NebulaLogger`` directly instead of the `String`
///   convenience.
public struct NebulaLogEvent: Sendable, Equatable {
    /// The category the event was emitted under.
    public let category: NebulaLogCategory
    /// The event's level.
    public let level: NebulaLogLevel
    /// The interpolated, already-redacted message string.
    public let message: String
    /// The instant the event was captured.
    public let date: Date

    /// Creates a log event.
    public init(category: NebulaLogCategory, level: NebulaLogLevel, message: String, date: Date = Date()) {
        self.category = category
        self.level = level
        self.message = message
        self.date = date
    }
}
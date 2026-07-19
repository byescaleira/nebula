//
//  NebulaLogger.swift
//  Nebula
//
//  A Sendable facade over `os.Logger`.
//
//  IMPORTANT — os.Logger cannot be wrapped: its level methods carry
//  `@_semantics("oslog.requires_constant_arguments")` and `log(level:_:)`
//  carries `oslog.log_with_level`, BOTH of which reject a forwarded
//  `OSLogMessage` parameter ("argument must be a string interpolation"). The
//  privacy-redacting `OSLogMessage` literal MUST appear directly at an
//  `os.Logger` call site. Nebula therefore exposes the underlying `os.Logger`
//  (``osLogger``) as the redaction-preserving path, and offers `String`
//  convenience level methods (which build a literal at the call site, so they
//  compile) for the common, non-redaction-sensitive case. See
//  vault/01-fundamentos/nebula-logging.md (Corrections).
//

import Foundation
import os

/// A `Sendable` facade over `os.Logger`.
///
/// Because `os.Logger` cannot be wrapped (its `OSLogMessage`-forwarding methods
/// reject a non-literal parameter), NebulaLogger exposes the underlying
/// `os.Logger` via ``osLogger`` for the **redaction-preserving path**, and
/// offers `String` convenience level methods for the **simple path**:
///
/// ```swift
/// let logger = NebulaLogger(subsystem: "com.acme.app", category: .networking)
///
/// // Redaction-sensitive: call os.Logger directly with a literal.
/// logger.osLogger.error("Failed \(url, privacy: .public) token=\(token, privacy: .private)")
///
/// // Simple dynamic String (defaults to `.public` — no per-argument redaction).
/// logger.error("retry \(attempt)")
/// ```
///
/// `NebulaLogger` is a value type with `let` storage holding an `os.Logger`
/// (itself `@unchecked Sendable`), so `Sendable` is soundly derived without
/// authoring `@unchecked` on Nebula's own type.
public struct NebulaLogger: Sendable {
    /// The underlying `os.Logger`. `@usableFromInline` for inline convenience
    /// methods.
    @usableFromInline
    let logger: os.Logger

    /// The subsystem this logger reports under (typically the consumer's
    /// bundle identifier).
    public let subsystem: String
    /// The category this logger reports under.
    public let category: NebulaLogCategory

    /// Creates a logger for the given `subsystem` and `category`.
    public init(subsystem: String, category: NebulaLogCategory) {
        self.subsystem = subsystem
        self.category = category
        self.logger = os.Logger(subsystem: subsystem, category: category.rawValue)
    }

    /// The underlying `os.Logger`. Use this for the redaction-preserving path:
    /// pass an `OSLogMessage` literal directly (per-argument `.public`/`.private`/
    /// `.sensitive`/`.auto` and `.private(mask: .hash)` are honored in
    /// Console.app, per WWDC20 10168).
    public var osLogger: os.Logger { logger }

    /// Returns `true` if a message at `level` would be emitted by `os.Logger`
    /// for this logger's subsystem/category at the current system configuration.
    public func isEnabled(_ level: NebulaLogLevel) -> Bool {
        logger.isEnabled(type: level.osLogType)
    }

    // MARK: - Simple path (String convenience, `.public` — no per-arg redaction)
    //
    // These build an `OSLogMessage` literal AT the os.Logger call site (so they
    // compile under `oslog.log_with_level`). The message is already a `String`,
    // so per-argument privacy redaction is NOT available here — use
    // ``osLogger`` for that.

    /// Logs a debug message (`OSLogType.debug`), redacted to `.public`.
    public func debug(_ message: String)  { logger.log(level: .debug,   "\(message, privacy: .public)") }
    /// Logs an info message (`OSLogType.info`), redacted to `.public`.
    public func info(_ message: String)   { logger.log(level: .info,    "\(message, privacy: .public)") }
    /// Logs a notice message (`OSLogType.default`), redacted to `.public`.
    public func notice(_ message: String) { logger.log(level: .default, "\(message, privacy: .public)") }
    /// Logs a warning message (`OSLogType.error`, matching `Logger.warning`), redacted to `.public`.
    public func warning(_ message: String) { logger.log(level: .error,   "\(message, privacy: .public)") }
    /// Logs an error message (`OSLogType.error`), redacted to `.public`.
    public func error(_ message: String)  { logger.log(level: .error,   "\(message, privacy: .public)") }
    /// Logs a fault message (`OSLogType.fault`), redacted to `.public`.
    public func fault(_ message: String)  { logger.log(level: .fault,   "\(message, privacy: .public)") }

    /// Logs `message` at the given Nebula level via the simple `String` path.
    public func log(_ level: NebulaLogLevel, _ message: String) {
        logger.log(level: level.osLogType, "\(message, privacy: .public)")
    }

    /// The signposter for this logger, backed by `OSSignposter(logger:)` and
    /// sharing its subsystem/category. Instruments-integrated measurement for
    /// free (WWDC18 405).
    public var signposter: NebulaSignposter { NebulaSignposter(logger: logger, subsystem: subsystem, category: category) }
}
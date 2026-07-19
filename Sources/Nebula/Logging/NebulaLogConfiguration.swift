//
//  NebulaLogConfiguration.swift
//  Nebula
//
//  A Sendable configuration value carrying the logging contract (subsystem,
//  category, min level, enabled flag, and a @Sendable handler for fan-out).
//  Fluent .with* builders mirror the Cosmos sibling's CosmosLogConfiguration
//  WITHOUT SwiftUI @Entry/@Observable — Nebula is a foundation. See
//  vault/01-fundamentos/nebula-logging.md.
//

import Foundation
import os

/// The Nebula logging configuration.
///
/// A `Sendable` value (NOT `Equatable` — it stores a `@Sendable` closure, which
/// cannot be compared) describing how logging is emitted and routed:
///
/// - ``isEnabled`` gates the secondary handler fan-out path;
/// - ``subsystem``/``category`` scope logs in Console.app and Instruments;
/// - ``minLevel`` filters the secondary `String` path;
/// - ``handler`` is invoked with a ``NebulaLogEvent`` on every emitted
///   secondary-path message (e.g. an in-memory sink for tests).
///
/// The contract follows the Cosmos sibling pattern — `Sendable` struct +
/// `@Sendable` handler + fluent `.with*` builders — but with no SwiftUI
/// `@Entry`/`@Observable`: a foundation does not own UI-thread affinity, so
/// configurations are constructed and passed explicitly.
///
/// ## Two emission paths
///
/// The **primary** path forwards an `OSLogMessage` straight to `os.Logger` via
/// ``NebulaLogger``, preserving per-argument privacy redaction — use it when
/// redaction matters. The **secondary** path here takes a dynamic `String`,
/// gates on `isEnabled && level >= minLevel`, emits to `os.Logger` as
/// `\(message, privacy: .public)` **and** invokes ``handler``. It loses
/// per-argument redaction (defaults `.public`) but lets sinks capture events
/// as plain ``NebulaLogEvent`` values.
public struct NebulaLogConfiguration: Sendable {
    /// Whether the secondary handler fan-out path is enabled.
    public let isEnabled: Bool
    /// The subsystem logs are reported under (the consumer's bundle identifier).
    public let subsystem: String
    /// The category logs are reported under.
    public let category: NebulaLogCategory
    /// The minimum level emitted on the secondary `String` path.
    public let minLevel: NebulaLogLevel
    /// Invoked with a ``NebulaLogEvent`` on every secondary-path emission.
    public let handler: @Sendable (NebulaLogEvent) -> Void

    /// Creates a configuration.
    public init(
        isEnabled: Bool = true,
        subsystem: String = NebulaLogConfiguration.defaultSubsystem,
        category: NebulaLogCategory = .general,
        minLevel: NebulaLogLevel = .info,
        handler: @escaping @Sendable (NebulaLogEvent) -> Void = { _ in }
    ) {
        self.isEnabled = isEnabled
        self.subsystem = subsystem
        self.category = category
        self.minLevel = minLevel
        self.handler = handler
    }

    /// The placeholder default subsystem. Consumers SHOULD override it with
    /// their bundle-id-derived subsystem via ``withSubsystem(_:)`` to avoid
    /// cross-app category collisions in Console.app.
    public static let defaultSubsystem = "com.nebula.foundation"

    /// The default configuration. Idempotent via the once-token `static let`
    /// initializer side-effect (no lock primitive). Override pieces with the
    /// `.with*` builders.
    public static let `default` = NebulaLogConfiguration()

    // MARK: - Fluent builders

    /// Returns a copy with the subsystem replaced.
    public func withSubsystem(_ subsystem: String) -> NebulaLogConfiguration {
        .init(isEnabled: isEnabled, subsystem: subsystem, category: category, minLevel: minLevel, handler: handler)
    }

    /// Returns a copy with the category replaced.
    public func withCategory(_ category: NebulaLogCategory) -> NebulaLogConfiguration {
        .init(isEnabled: isEnabled, subsystem: subsystem, category: category, minLevel: minLevel, handler: handler)
    }

    /// Returns a copy with the minimum level replaced.
    public func withMinLevel(_ minLevel: NebulaLogLevel) -> NebulaLogConfiguration {
        .init(isEnabled: isEnabled, subsystem: subsystem, category: category, minLevel: minLevel, handler: handler)
    }

    /// Returns a copy with the handler replaced.
    public func withHandler(_ handler: @escaping @Sendable (NebulaLogEvent) -> Void) -> NebulaLogConfiguration {
        .init(isEnabled: isEnabled, subsystem: subsystem, category: category, minLevel: minLevel, handler: handler)
    }

    /// Returns a copy with `isEnabled` replaced.
    public func withEnabled(_ isEnabled: Bool) -> NebulaLogConfiguration {
        .init(isEnabled: isEnabled, subsystem: subsystem, category: category, minLevel: minLevel, handler: handler)
    }

    // MARK: - Emission

    /// Builds a ``NebulaLogger`` for this configuration's subsystem/category.
    public func logger() -> NebulaLogger {
        NebulaLogger(subsystem: subsystem, category: category)
    }

    /// The secondary emission path: a dynamic `String` convenience that gates on
    /// `isEnabled && level >= minLevel`, emits to `os.Logger` as
    /// `\(message, privacy: .public)`, and invokes ``handler``.
    ///
    /// - Note: This path loses per-argument privacy redaction (the message is
    ///   already interpolated to `.public`). For redaction-sensitive logging,
    ///   use ``logger()`` / ``NebulaLogger`` directly with an `OSLogMessage`.
    public func log(_ level: NebulaLogLevel, _ message: String) {
        guard isEnabled, level >= minLevel else { return }
        logger().log(level, message)
        handler(NebulaLogEvent(category: category, level: level, message: message))
    }
}
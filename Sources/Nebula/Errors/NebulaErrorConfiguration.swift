//
//  NebulaErrorConfiguration.swift
//  Nebula
//
//  A Sendable error-handler configuration + a Sendable, Equatable event. Mirrors
//  CosmosErrorConfiguration without SwiftUI. Sendable ONLY (NOT Equatable) —
//  the stored @Sendable handler closure is not Equatable. See
//  vault/01-fundamentos/nebula-errors.md.
//

import Foundation

/// A `Sendable` snapshot of an error report, carried into the handler.
///
/// Unlike an `any Error`, ``error`` is a `Sendable` `NebulaError`, so it can
/// cross actor boundaries inside a `@Sendable` handler.
public struct NebulaErrorEvent: Sendable, Equatable {
    /// The category the error was reported under.
    public let category: String
    /// The reported error (Sendable).
    public let error: NebulaError
    /// When the error was reported.
    public let date: Date

    /// Creates an error event.
    public init(category: String, error: NebulaError, date: Date = Date()) {
        self.category = category
        self.error = error
        self.date = date
    }
}

/// The Nebula error-reporting configuration.
///
/// `Sendable` ONLY (NOT `Equatable` — it stores a `@Sendable` closure, which is
/// not `Equatable`; synthesized `Equatable` is rejected, mirroring
/// `CosmosErrorConfiguration`). Describes how errors are reported:
///
/// - ``isEnabled`` gates reporting;
/// - ``category`` tags reported events;
/// - ``handler`` is invoked with a ``NebulaErrorEvent`` on every reported error.
///
/// Like ``NebulaLogConfiguration``, this is an immutable `Sendable` struct with
/// fluent `.with*` builders — a foundation does not own UI-thread affinity, so
/// configurations are constructed and passed explicitly (no SwiftUI
/// `@Environment`).
public struct NebulaErrorConfiguration: Sendable {
    /// Whether reporting is enabled.
    public let isEnabled: Bool
    /// The category reported events are tagged with.
    public let category: String
    /// Invoked with a ``NebulaErrorEvent`` on every reported error.
    public let handler: @Sendable (NebulaErrorEvent) -> Void

    /// Creates a configuration.
    public init(
        isEnabled: Bool = true,
        category: String = "Nebula",
        handler: @escaping @Sendable (NebulaErrorEvent) -> Void = { _ in }
    ) {
        self.isEnabled = isEnabled
        self.category = category
        self.handler = handler
    }

    /// The default configuration. Idempotent via the once-token `static let`
    /// initializer side-effect (no lock primitive).
    public static let `default` = NebulaErrorConfiguration()

    // MARK: - Fluent builders

    /// Returns a copy with `isEnabled` replaced.
    public func withEnabled(_ isEnabled: Bool) -> NebulaErrorConfiguration {
        .init(isEnabled: isEnabled, category: category, handler: handler)
    }

    /// Returns a copy with the category replaced.
    public func withCategory(_ category: String) -> NebulaErrorConfiguration {
        .init(isEnabled: isEnabled, category: category, handler: handler)
    }

    /// Returns a copy with the handler replaced.
    public func withHandler(_ handler: @escaping @Sendable (NebulaErrorEvent) -> Void) -> NebulaErrorConfiguration {
        .init(isEnabled: isEnabled, category: category, handler: handler)
    }

    // MARK: - Reporting

    /// Reports `error` to ``handler`` as a ``NebulaErrorEvent``, gated on
    /// ``isEnabled``.
    public func report(_ error: NebulaError) {
        guard isEnabled else { return }
        handler(NebulaErrorEvent(category: category, error: error))
    }
}
//
//  NebulaErrorConfiguration.swift
//  Nebula
//
//  A Sendable error-handler configuration + a Sendable, Equatable event. Mirrors
//  CosmosErrorConfiguration without SwiftUI. Sendable ONLY (NOT Equatable) —
//  the stored @Sendable handler closure is not Equatable, and the Wave N12
//  user-message map adds a second @Sendable closure (also not Equatable). See
//  vault/01-fundamentos/nebula-errors.md and vault/03-padroes/nebula-user-error.md.
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
/// `Sendable` ONLY (NOT `Equatable` — it stores `@Sendable` closures, which are
/// not `Equatable`; synthesized `Equatable` is rejected, mirroring
/// `CosmosErrorConfiguration`). Describes how errors are reported and mapped
/// to user-facing values:
///
/// - ``isEnabled`` gates reporting;
/// - ``category`` tags reported events;
/// - ``handler`` is invoked with a ``NebulaErrorEvent`` on every reported error;
/// - ``userMessageMap`` maps a reported ``NebulaError`` to an optional
///   ``NebulaUserError`` for the presentation layer (Wave N12).
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
    /// Maps a reported ``NebulaError`` to an optional ``NebulaUserError`` for the
    /// presentation layer. Keyed by the error's ``NebulaError/Kind`` and its
    /// ``NebulaError/metadata`` (runtime context for interpolation). The default
    /// `{ _ in nil }` means no user-facing value unless the app configures one.
    public let userMessageMap: @Sendable (NebulaError.Kind, [String: String]) -> NebulaUserError?

    /// Creates a configuration.
    public init(
        isEnabled: Bool = true,
        category: String = "Nebula",
        handler: @escaping @Sendable (NebulaErrorEvent) -> Void = { _ in },
        userMessageMap: @escaping @Sendable (NebulaError.Kind, [String: String]) -> NebulaUserError? = { _, _ in nil }
    ) {
        self.isEnabled = isEnabled
        self.category = category
        self.handler = handler
        self.userMessageMap = userMessageMap
    }

    /// The default configuration. Idempotent via the once-token `static let`
    /// initializer side-effect (no lock primitive).
    public static let `default` = NebulaErrorConfiguration()

    // MARK: - Fluent builders

    /// Returns a copy with `isEnabled` replaced.
    public func withEnabled(_ isEnabled: Bool) -> NebulaErrorConfiguration {
        .init(isEnabled: isEnabled, category: category, handler: handler, userMessageMap: userMessageMap)
    }

    /// Returns a copy with the category replaced.
    public func withCategory(_ category: String) -> NebulaErrorConfiguration {
        .init(isEnabled: isEnabled, category: category, handler: handler, userMessageMap: userMessageMap)
    }

    /// Returns a copy with the handler replaced.
    public func withHandler(_ handler: @escaping @Sendable (NebulaErrorEvent) -> Void) -> NebulaErrorConfiguration {
        .init(isEnabled: isEnabled, category: category, handler: handler, userMessageMap: userMessageMap)
    }

    /// Returns a copy with the user-message map replaced. The map is keyed by
    /// the error's ``NebulaError/Kind`` and its ``NebulaError/metadata``
    /// dictionary (runtime context for interpolation) and returns an optional
    /// ``NebulaUserError`` (a map can decline to surface a kind by returning
    /// `nil`). The default map is `{ _, _ in nil }` (opt-in). Wire the shipped
    /// English fallback via
    /// `.withUserMessageMap { NebulaUserError.default(for: $0, context: $1) }`.
    public func withUserMessageMap(
        _ map: @escaping @Sendable (NebulaError.Kind, [String: String]) -> NebulaUserError?
    ) -> NebulaErrorConfiguration {
        .init(isEnabled: isEnabled, category: category, handler: handler, userMessageMap: map)
    }

    // MARK: - Reporting

    /// Reports `error` to ``handler`` as a ``NebulaErrorEvent``, gated on
    /// ``isEnabled``.
    public func report(_ error: NebulaError) {
        guard isEnabled else { return }
        handler(NebulaErrorEvent(category: category, error: error))
    }

    // MARK: - User-error bridge

    /// Resolves an optional ``NebulaUserError`` for `error` via
    /// ``userMessageMap``, passing the error's ``NebulaError/Kind`` and
    /// ``NebulaError/metadata``. **Not** gated on ``isEnabled`` — user-message
    /// mapping is orthogonal to reporting (an app can surface a user-facing
    /// value whether or not errors are reported). Returns `nil` when the map
    /// declines to surface the kind (the default map always returns `nil`).
    public func userError(for error: NebulaError) -> NebulaUserError? {
        userMessageMap(error.kind, error.metadata)
    }
}
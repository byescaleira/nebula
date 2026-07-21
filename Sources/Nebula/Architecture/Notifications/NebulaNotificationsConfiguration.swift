//
//  NebulaNotificationsConfiguration.swift
//  Nebula
//
//  Wave N15a — App-readiness. A `Sendable` configuration value carrying the
// notification callback contract: two `@Sendable` synchronous-returning
// handlers (`willPresent` / `didReceive`). Mirrors ``NebulaLogConfiguration``
// (Sendable struct, NOT `Equatable` — it stores `@Sendable` closures, which
// cannot be compared). Fluent `.with*` builders; `static let default`. See
// vault/03-padroes/nebula-notifications.md.
//
//  The handlers are SYNCHRONOUS-RETURNING (not completion-callback based):
// `willPresent` returns the presentation options directly; `didReceive`
// returns `Void` (the SDK's ack completion is invoked synchronously after the
// handler runs). This avoids capturing the SDK's non-`@Sendable` Objective-C
// completion handler inside a `@Sendable` closure — a Swift 6 strict-concurrency
// wall the completion-callback shape would hit. The decision is documented in
// <doc:ArchitectureNotifications>.
//

import Foundation

/// The Nebula notification configuration.
///
/// A `Sendable` value (NOT `Equatable` — it stores `@Sendable` closures) holding
/// the two callback handlers the façade forwards to:
///
/// - ``willPresent`` — invoked when a notification arrives while the app is
///   foregrounded. Returns the ``NebulaNotificationPresentationOptions`` to show.
///   The default returns `[.banner, .sound]`.
/// - ``didReceive`` — invoked when the user interacts with a notification. The
///   default is a no-op. (Only fires on non-tvOS — tvOS does not surface
///   notification responses.)
///
/// The handlers are **synchronous-returning** rather than completion-callback
/// based: `willPresent` returns the options directly and `didReceive` returns
/// `Void`, after which the façade invokes the SDK's completion synchronously.
/// This avoids capturing the SDK's non-`@Sendable` Objective-C completion
/// handler inside a `@Sendable` closure — a Swift 6 strict-concurrency wall the
/// completion-callback shape would hit. A handler that needs to defer the
/// decision should capture state and resolve it out-of-band.
public struct NebulaNotificationsConfiguration: Sendable {

    /// Decides the presentation options for a foreground notification.
    ///
    /// Invoked synchronously by the façade on the delegate's thread; the returned
    /// options are passed straight to `UNUserNotificationCenter`.
    public let willPresent: @Sendable (NebulaNotificationRequest) -> NebulaNotificationPresentationOptions

    /// Handles the user's interaction with a notification.
    ///
    /// Invoked synchronously by the façade on the delegate's thread; the façade
    /// acks the SDK immediately after the handler returns. Only fires on
    /// non-tvOS (tvOS does not surface notification responses).
    public let didReceive: @Sendable (NebulaNotificationResponse) -> Void

    /// Creates a configuration.
    public init(
        willPresent: @escaping @Sendable (NebulaNotificationRequest) -> NebulaNotificationPresentationOptions = { _ in [.banner, .sound] },
        didReceive: @escaping @Sendable (NebulaNotificationResponse) -> Void = { _ in }
    ) {
        self.willPresent = willPresent
        self.didReceive = didReceive
    }

    /// The default configuration (banner + sound on foreground; no-op on tap).
    public static let `default` = NebulaNotificationsConfiguration()

    // MARK: - Fluent builders

    /// Returns a copy with the `willPresent` handler replaced.
    public func withWillPresent(_ handler: @escaping @Sendable (NebulaNotificationRequest) -> NebulaNotificationPresentationOptions) -> NebulaNotificationsConfiguration {
        .init(willPresent: handler, didReceive: didReceive)
    }

    /// Returns a copy with the `didReceive` handler replaced.
    public func withDidReceive(_ handler: @escaping @Sendable (NebulaNotificationResponse) -> Void) -> NebulaNotificationsConfiguration {
        .init(willPresent: willPresent, didReceive: handler)
    }
}
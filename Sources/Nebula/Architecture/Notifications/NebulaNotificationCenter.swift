//
//  NebulaNotificationCenter.swift
//  Nebula
//
//  Wave N15a — App-readiness. The architecture seam over the notification
// scheduling/authorization surface: a `Sendable` port a test double conforms to
// (the ``NebulaUNNotificationCenter`` façade is the concrete adapter over
// `UNUserNotificationCenter`). The delegate-handlers surface (willPresent /
// didReceive) is NOT on the port — it lives on the config (the façade forwards);
// the port is the testable scheduling/authorization surface. See
// vault/03-padroes/nebula-notifications.md.
//

import Foundation

/// A `Sendable` notification scheduling/authorization port.
///
/// The architecture seam for `UNUserNotificationCenter`'s scheduling surface —
/// `requestAuthorization` / `add` / `cancel` / `cancelAll` / `pendingRequests`.
/// An app swaps the backing center (a test double, a remote-push-driven store)
/// by conforming to this port directly. The concrete adapter is
/// ``NebulaUNNotificationCenter`` (a `final class` over
/// `UNUserNotificationCenter.current()` that also conforms to
/// `UNUserNotificationCenterDelegate`, forwarding foreground/notification-tap
/// callbacks to the `@Sendable` handlers in ``NebulaNotificationsConfiguration``).
///
/// The delegate-handlers surface is **not** on the port — it lives on the config.
public protocol NebulaNotificationCenter: Sendable {

    /// Requests authorization for the given `options`. Returns whether the user
    /// granted permission. Throws on a system error (the bridge preserves the
    /// underlying `UNError`/`NSError`).
    func requestAuthorization(options: NebulaAuthorizationOptions) async throws -> Bool

    /// Schedules `request`. Throws on a system error (invalid trigger,
    /// not-authorized, etc.).
    func add(_ request: NebulaNotificationRequest) async throws

    /// Cancels the pending requests with the given `identifiers` (no-op if absent).
    func cancel(_ identifiers: [String]) async

    /// Cancels all pending requests.
    func cancelAll() async

    /// Returns the currently-pending requests (mapped to Nebula values).
    func pendingRequests() async -> [NebulaNotificationRequest]
}
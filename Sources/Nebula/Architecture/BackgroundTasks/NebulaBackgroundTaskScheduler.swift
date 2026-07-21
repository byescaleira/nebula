//
//  NebulaBackgroundTaskScheduler.swift
//  Nebula
//
//  Wave N15b — App-readiness. The architecture seam over the background-task
//  scheduling surface: a `Sendable` port a test double conforms to (the
//  ``NebulaBGTaskScheduler`` façade is the concrete adapter over
//  `BGTaskScheduler.shared`). The launch-handler surface is NOT on the port —
//  it lives on the config (the façade forwards); the port is the testable
//  scheduling/register surface. See vault/03-padroes/nebula-background-tasks.md.
//

import Foundation

/// A `Sendable` background-task scheduling port.
///
/// The architecture seam for `BGTaskScheduler.shared`'s scheduling surface —
/// `register` / `submit` / `cancel` / `cancelAll` / `pendingRequests`. An app
/// swaps the backing scheduler (a test double, a remote-driven store) by
/// conforming to this port directly. The concrete adapter is
/// ``NebulaBGTaskScheduler`` (a `final class` over `BGTaskScheduler.shared` that
/// bridges the system's launch callback to the `@Sendable` ``launch`` handler in
/// ``NebulaBackgroundTaskConfiguration``).
///
/// The launch-handler surface is **not** on the port — it lives on the config.
/// `register(_:)` returns whether the system accepted the identifier (it must
/// appear in the app's `BGTaskSchedulerPermittedIdentifiers` Info.plist array;
/// returns `false` otherwise).
public protocol NebulaBackgroundTaskScheduler: Sendable {

    /// Registers the identifier with the system so its launch callback can fire.
    /// Returns `false` if the identifier isn't in the app's permitted-identifiers
    /// list. Must be called before the app finishes launching.
    func register(_ identifier: String) async -> Bool

    /// Schedules `request`. Throws on a system error (not-permitted, too many
    /// pending, unavailable). Submitting a request with an existing identifier
    /// replaces the previous pending one.
    func submit(_ request: NebulaBackgroundTaskRequest) async throws

    /// Cancels the pending request with the given `identifier` (no-op if absent).
    func cancel(_ identifier: String) async

    /// Cancels all pending requests.
    func cancelAll() async

    /// Returns the currently-pending requests (mapped to Nebula values).
    func pendingRequests() async -> [NebulaBackgroundTaskRequest]
}
//
//  NebulaBackgroundTaskConfiguration.swift
//  Nebula
//
//  Wave N15b — App-readiness. A `Sendable` configuration value carrying the
// background-task launch contract: one `@Sendable` handler (`launch`) invoked
// when the system launches the app to perform a registered task. Mirrors
//  ``NebulaLogConfiguration`` / ``NebulaNotificationsConfiguration`` (Sendable
//  struct, NOT `Equatable` — it stores a `@Sendable` closure, which cannot be
//  compared). Fluent `.with*` builder; `static let default`. See
//  vault/03-padroes/nebula-background-tasks.md.
//
//  The launch handler is SYNCHRONOUS-RETURNING (`Void`): the system invokes it
//  on the register queue, the façade bridges the delivered `BGTask` to a
//  Sendable ``NebulaBackgroundTask`` handle, calls `launch(handle)`, and returns
//  (the system does not await the handler — the app signals completion later via
//  ``NebulaBackgroundTask/complete(success:)``). This avoids the SDK's
//  non-`Sendable` `BGTask` crossing into a `@Sendable` closure: the handle holds
//  only Sendable closures that reach the `BGTask` through the façade's
//  `Mutex<[String: BGTask]>` (the ``NebulaDefaults`` `Mutex<non-Sendable>`
//  precedent), so no `@unchecked Sendable` is needed. See
//  <doc:ArchitectureBackgroundTasks>.
//

import Foundation

/// The Nebula background-task configuration.
///
/// A `Sendable` value (NOT `Equatable` — it stores a `@Sendable` closure) holding
/// the launch handler the façade forwards to:
///
/// - ``launch`` — invoked when the system launches the app to perform a
///   registered task. Receives a Sendable ``NebulaBackgroundTask`` handle. The
///   default is a no-op.
///
/// The handler is **synchronous-`Void`-returning**: the system invokes it on the
/// register queue and the façade returns immediately; the app signals
/// completion out-of-band via the handle. A handler that performs long work
/// should detach it (the system gives the app limited background time and calls
/// the handle's expiration handler if it reclaims it).
public struct NebulaBackgroundTaskConfiguration: Sendable {

    /// Handles a system-initiated background-task launch.
    ///
    /// Invoked synchronously by the façade on the register queue when the system
    /// launches the app; receives a Sendable ``NebulaBackgroundTask`` handle to
    /// drive completion/expiration. The handler returns immediately and the app
    /// signals completion via ``NebulaBackgroundTask/complete(success:)`` once
    /// the work is done. The default is a no-op (the system will mark the task
    /// unsuccessful on expiry if no completion is signaled).
    public let launch: @Sendable (NebulaBackgroundTask) -> Void

    /// Creates a configuration.
    public init(
        launch: @escaping @Sendable (NebulaBackgroundTask) -> Void = { _ in }
    ) {
        self.launch = launch
    }

    /// The default configuration (no-op launch).
    public static let `default` = NebulaBackgroundTaskConfiguration()

    // MARK: - Fluent builders

    /// Returns a copy with the `launch` handler replaced.
    public func withLaunch(_ handler: @escaping @Sendable (NebulaBackgroundTask) -> Void) -> NebulaBackgroundTaskConfiguration {
        .init(launch: handler)
    }
}
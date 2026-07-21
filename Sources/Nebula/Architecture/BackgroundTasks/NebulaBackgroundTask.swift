//
//  NebulaBackgroundTask.swift
//  Nebula
//
//  Wave N15b — App-readiness. The Sendable launch-time handle the façade hands
//  to the config's `launch` handler. The system delivers a non-`Sendable`
//  `BGTask` inside the `@Sendable` launch callback; wrapping it directly would
//  force `@unchecked Sendable` (forbidden). Instead this handle holds only the
//  `identifier` + `kind` + two `@Sendable` closures (`complete` / `onExpiration`)
//  that capture the SENDABLE façade + identifier (NOT the `BGTask`) and call back
//  into `façade.finishTask(id, success:)` / `façade.setExpiration(id, handler:)`,
//  which reach the `BGTask` via the façade's `Mutex<[String: BGTask]>` live-task
//  map (the ``NebulaDefaults`` `Mutex<non-Sendable>` precedent). `Sendable` is
//  derived — no `@unchecked`. All-5 (no `BGTask` referenced here). See
//  vault/03-padroes/nebula-background-tasks.md.
//

import Foundation

/// The Sendable handle a ``NebulaBackgroundTaskConfiguration/launch`` handler
/// receives when the system launches the app to perform a background task.
///
/// This is a **Sendable launch-time handle**, not a wrapper around `BGTask`
/// (which is non-`Sendable` and system-delivered). The handle reaches the task's
/// lifecycle through the owning façade:
///
/// - ``complete(success:)`` — calls `BGTask.setTaskCompleted(success:)` on the
///   underlying task via the façade. Call this as soon as the background work is
///   done.
/// - ``onExpiration(_:)`` — assigns the `BGTask.expirationHandler`. Assign this
///   early to cancel ongoing work and clean up if the system reclaims time.
///
/// Because the handle stores `@Sendable` closures (which are not `Equatable`),
/// `==` compares the ``identifier`` and ``kind`` only — not the closures. Two
/// handles for the same identifier are equal even if their closures differ
/// (there is only ever one live task per identifier).
public struct NebulaBackgroundTask: Sendable, Equatable {

    /// The task identifier (matches ``NebulaBackgroundTaskRequest/identifier``
    /// and the `BGTask.identifier` the system delivered).
    public let identifier: String
    /// The task kind (app refresh / processing).
    public let kind: NebulaBackgroundTaskKind
    /// Reaches `BGTask.setTaskCompleted(success:)` via the façade. Built by the
    /// façade; captures only Sendable state.
    public let finish: @Sendable (Bool) -> Void
    /// Reaches `BGTask.expirationHandler` assignment via the façade. Built by the
    /// façade; captures only Sendable state. The inner closure is `@escaping`
    /// because it is the parameter of a stored (escaping) function type — Swift
    /// does not infer `@escaping` for the parameter of a `@Sendable` stored
    /// closure, so it is spelled explicitly.
    public let setExpiration: @Sendable (@escaping @Sendable () -> Void) -> Void

    /// Creates a handle. Apps do not construct this directly — the façade builds
    /// it inside the system's launch callback and passes it to
    /// ``NebulaBackgroundTaskConfiguration/launch``.
    public init(
        identifier: String,
        kind: NebulaBackgroundTaskKind,
        finish: @Sendable @escaping (Bool) -> Void,
        setExpiration: @Sendable @escaping (@escaping @Sendable () -> Void) -> Void
    ) {
        self.identifier = identifier
        self.kind = kind
        self.finish = finish
        self.setExpiration = setExpiration
    }

    /// Signals task completion to the system (forwards to
    /// `BGTask.setTaskCompleted(success:)` via the façade).
    public func complete(success: Bool) {
        finish(success)
    }

    /// Assigns the expiration handler the system calls shortly before the
    /// task's background time expires (forwards to `BGTask.expirationHandler`
    /// via the façade). Use it to cancel ongoing work and clean up.
    public func onExpiration(_ handler: @escaping @Sendable () -> Void) {
        setExpiration(handler)
    }

    /// Equality is by ``identifier`` and ``kind`` — the closures are not
    /// compared (a `@Sendable` closure is not `Equatable`). There is only ever
    /// one live task per identifier, so identity-by-identifier is correct.
    public static func == (lhs: NebulaBackgroundTask, rhs: NebulaBackgroundTask) -> Bool {
        lhs.identifier == rhs.identifier && lhs.kind == rhs.kind
    }
}
//
//  NebulaBackgroundTaskRequest.swift
//  Nebula
//
//  Wave N15b — App-readiness. The Nebula-owned background-task value types:
// the task kind (app refresh / processing) and the scheduling request. All-5,
//  `Sendable`-derived, no `@available` gate — these are Nebula values, NOT
//  `BGTaskRequest` / `BGProcessingTaskRequest`. The SDK request subclasses are
//  `API_UNAVAILABLE(macos) API_UNAVAILABLE(watchos)` on the SDK type, but a
//  Nebula value type is free of that constraint; the platform restriction applies
//  only where the façade TOUCHES the SDK (see ``NebulaBGTaskScheduler``). See
//  vault/03-padroes/nebula-background-tasks.md.
//

import Foundation

/// The kind of system-initiated background task.
///
/// A `Sendable` enum mirroring the all-supported-platforms `BGTask` subclasses
/// this wave ships: `.appRefresh` (short content refresh — `BGAppRefreshTask`)
/// and `.processing` (long deferrable work — `BGProcessingTask`). The
/// iOS-26-only `BGContinuedProcessingTask` (user-initiated, presents UI) is
/// **deferred** to N15c.
public enum NebulaBackgroundTaskKind: Sendable, Equatable, Hashable, CaseIterable, CustomStringConvertible {

    /// A short content-refresh task (`BGAppRefreshTask`).
    case appRefresh
    /// A long, deferrable processing task (`BGProcessingTask`).
    case processing

    /// Mirrors the case name.
    public var description: String {
        switch self {
        case .appRefresh: return "appRefresh"
        case .processing: return "processing"
        }
    }
}

/// A Nebula-owned background-task scheduling request.
///
/// Wraps an identifier + kind + earliest-begin date + the two processing-only
/// conditions (`requiresNetworkConnectivity`, `requiresExternalPower`). The
/// concrete `BGTaskRequest` subclass is built by
/// ``NebulaBGTaskScheduler/submit(_:)`` when scheduling. `requiresNetworkConnectivity`
/// and `requiresExternalPower` are ignored for `.appRefresh` (they live only on
/// `BGProcessingTaskRequest`); the façade applies them only for `.processing`.
public struct NebulaBackgroundTaskRequest: Sendable, Equatable, Hashable {

    /// A unique identifier for the request (must appear in the app's
    /// `BGTaskSchedulerPermittedIdentifiers` Info.plist array; submitting a
    /// request with an existing identifier replaces the previous pending one).
    public let identifier: String
    /// The task kind (determines which `BGTaskRequest` subclass the façade builds).
    public let kind: NebulaBackgroundTaskKind
    /// The earliest date at which to run the task, or `nil` for no start delay.
    /// The system does not guarantee launching at this date, only that it won't
    /// begin sooner.
    public let earliestBeginDate: Date?
    /// Processing-only: if `true`, the system launches the app only when the
    /// device has network connectivity. Ignored for `.appRefresh`.
    public let requiresNetworkConnectivity: Bool
    /// Processing-only: if `true`, the system launches the app only while the
    /// device is connected to external power. Ignored for `.appRefresh`.
    public let requiresExternalPower: Bool

    /// Creates a request.
    public init(
        identifier: String,
        kind: NebulaBackgroundTaskKind,
        earliestBeginDate: Date? = nil,
        requiresNetworkConnectivity: Bool = false,
        requiresExternalPower: Bool = false
    ) {
        self.identifier = identifier
        self.kind = kind
        self.earliestBeginDate = earliestBeginDate
        self.requiresNetworkConnectivity = requiresNetworkConnectivity
        self.requiresExternalPower = requiresExternalPower
    }
}
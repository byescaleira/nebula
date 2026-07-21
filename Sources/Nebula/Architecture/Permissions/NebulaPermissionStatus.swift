//
//  NebulaPermissionStatus.swift
//  Nebula
//
//  Wave N15a — App-readiness. A `Sendable` permission-status value: the union
// superset of Apple's per-framework status vocabularies (AVFoundation /
// CoreLocation / Photos / AppTrackingTransparency / UserNotifications), so a
// future `NebulaPermissions` request port maps each framework's status into one
// type. N15a ships only the value plus the `UNAuthorizationStatus` bridge (the
// one status source in scope); the AV/CL/PH/ATT bridges come with the deferred
// `NebulaPermissions` port. All-5, no `@available` gate — `UserNotifications` is
// available on every platform at the `.v26` floor. See
// vault/03-padroes/nebula-notifications.md.
//
//  NOTE: `UNAuthorizationStatus.ephemeral` is `API_UNAVAILABLE(macos, watchos,
// tvos)` (iOS-14-only, App Clips). The `case .ephemeral` arm of the bridge is
// therefore `#if os(iOS)` — the case still exists in `NebulaPermissionStatus`
// on all platforms (a future non-UN bridge may produce it), but only the iOS
// UN bridge fills it.
//

import Foundation
import UserNotifications

/// A `Sendable` permission-status value spanning Apple's permission frameworks.
///
/// There is no unified Apple permissions API — `AVCaptureDevice`,
/// `CLLocationManager`, `PHPhotoLibrary`, `ATTrackingManager`, and
/// `UNUserNotificationCenter` each expose a distinct status enum. This type is a
/// union superset so a future `NebulaPermissions` request port can map each
/// framework's status into one value. N15a ships the value plus the
/// ``init(_:)`` bridge from `UNAuthorizationStatus` (the one status source in
/// scope); the AV/CL/PH/ATT bridges ship with the deferred `NebulaPermissions`
/// port (app-level glue — see the *Permissions* article).
///
/// `Sendable`, `Equatable`, `Hashable`, and `CaseIterable` are derived. The type
/// carries no framework state, so it crosses actor boundaries freely.
public enum NebulaPermissionStatus: Sendable, Equatable, Hashable, CaseIterable, CustomStringConvertible {

    /// The user has not yet been asked (no determination made).
    case notDetermined
    /// Permission is restricted (e.g. parental controls, MDM) — the app cannot
    /// request, and the user cannot grant. Distinct from `denied`.
    case restricted
    /// The user explicitly denied permission.
    case denied
    /// The user granted permission.
    case authorized
    /// The user granted provisional (non-interruptive) permission (UN/CL).
    case provisional
    /// The user granted ephemeral (session-scoped) permission (iOS App Clips).
    case ephemeral
    /// The user granted "always" permission (CoreLocation).
    case authorizedAlways
    /// The user granted "while in use" permission (CoreLocation).
    case authorizedWhenInUse

    /// A stable, debuggable description (e.g. `NebulaPermissionStatus.authorized`).
    public var description: String {
        switch self {
        case .notDetermined:        return "NebulaPermissionStatus.notDetermined"
        case .restricted:          return "NebulaPermissionStatus.restricted"
        case .denied:             return "NebulaPermissionStatus.denied"
        case .authorized:         return "NebulaPermissionStatus.authorized"
        case .provisional:        return "NebulaPermissionStatus.provisional"
        case .ephemeral:          return "NebulaPermissionStatus.ephemeral"
        case .authorizedAlways:   return "NebulaPermissionStatus.authorizedAlways"
        case .authorizedWhenInUse: return "NebulaPermissionStatus.authorizedWhenInUse"
        }
    }

    /// Bridges a `UNAuthorizationStatus` into this enum.
    ///
    /// `.notDetermined` / `.denied` / `.authorized` / `.provisional` map 1:1.
    /// `.ephemeral` is iOS-only (App Clips) and bridges on iOS only. Returns
    /// `nil` for any other `UNAuthorizationStatus` case that has no Nebula
    /// equivalent (UN has no `restricted` / `authorizedAlways` /
    /// `authorizedWhenInUse`; and SDK-added cases on any platform — e.g. a new
    /// visionOS case — fall through to `default`). A plain `default` (not
    /// `@unknown default`) keeps the switch exhaustive on every platform even
    /// when the C enum is imported frozen and gains a case under a newer SDK.
    public init?(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .denied:       self = .denied
        case .authorized:   self = .authorized
        case .provisional:  self = .provisional
        #if os(iOS)
        case .ephemeral:    self = .ephemeral
        #endif
        default:            return nil
        }
    }
}
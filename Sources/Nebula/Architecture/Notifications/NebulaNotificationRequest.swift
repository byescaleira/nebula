//
//  NebulaNotificationRequest.swift
//  Nebula
//
//  Wave N15a — App-readiness. The Nebula-owned notification value types:
// content / trigger / request / response, plus the two `OptionSet`s
// (presentation options, authorization options). All-5, `Sendable`-derived, no
// `@available` gate — these are Nebula values, NOT `UNNotificationContent` etc.
// The SDK props (`title` / `body` / `userInfo` …) are `API_UNAVAILABLE(tvos)` on
// the SDK type, but a Nebula value type is free of that constraint; the tvOS
// gate lives only where the façade TOUCHES the SDK (see
// ``NebulaUNNotificationCenter``). See vault/03-padroes/nebula-notifications.md.
//

import Foundation

/// The Nebula-owned notification payload (title / subtitle / body / userInfo).
///
/// A `Sendable` value type — distinct from `UNMutableNotificationContent`,
/// whose user-facing properties are `API_UNAVAILABLE(tvos)`. This Nebula value
/// is all-5; the tvOS restriction applies only when the façade copies it into a
/// `UNMutableNotificationContent` (gated `#if !os(tvOS)` there). `userInfo` is
/// kept to `[String: String]` for `Sendable` simplicity in this wave.
public struct NebulaNotificationContent: Sendable, Equatable, Hashable {

    /// The notification title.
    public var title: String
    /// The notification subtitle.
    public var subtitle: String
    /// The notification body.
    public var body: String
    /// Free-form string metadata (`UNNotificationContent.userInfo` is
    /// `[AnyHashable: Any]`; this wave narrows it to `[String: String]` for
    /// `Sendable` simplicity).
    public var userInfo: [String: String]

    /// Creates a content value.
    public init(title: String = "", subtitle: String = "", body: String = "", userInfo: [String: String] = [:]) {
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.userInfo = userInfo
    }
}

/// A Nebula-owned notification trigger.
///
/// A `Sendable` enum mirroring the all-5 `UNNotificationTrigger` subclasses
/// that this wave supports: `.timeInterval` and `.calendar`. The `.location`
/// case (iOS+watchOS only, needs `CoreLocation`) is **deferred** to a follow-up.
public enum NebulaNotificationTrigger: Sendable, Equatable, Hashable {

    /// Fires after `timeInterval` seconds.
    case timeInterval(TimeInterval)
    /// Fires at the next date matching `components`.
    case calendar(DateComponents)
}

/// A Nebula-owned scheduled notification request.
///
/// Wraps an identifier + content + trigger. The concrete `UNNotificationRequest`
/// is built by ``NebulaUNNotificationCenter/add(_:)`` when scheduling.
public struct NebulaNotificationRequest: Sendable, Equatable, Hashable {

    /// A unique identifier for the request (duplicate identifiers replace the
    /// existing pending request).
    public let identifier: String
    /// The payload.
    public let content: NebulaNotificationContent
    /// The trigger, or `nil` to deliver immediately.
    public let trigger: NebulaNotificationTrigger?

    /// Creates a request.
    public init(identifier: String, content: NebulaNotificationContent, trigger: NebulaNotificationTrigger? = nil) {
        self.identifier = identifier
        self.content = content
        self.trigger = trigger
    }
}

/// The presentation options a ``NebulaNotificationsConfiguration/willPresent``
/// handler returns (which UI to show while the app is foregrounded).
///
/// A `Sendable` `OptionSet` mirroring the all-5 `UNNotificationPresentationOptions`
/// (`.badge` / `.sound` / `.banner` / `.list`). UI rendering itself is a Cosmos
/// concern — Nebula only carries the option value.
public struct NebulaNotificationPresentationOptions: OptionSet, Sendable, Equatable, Hashable {

    /// Raw values mirror `UNNotificationPresentationOptions` so the façade maps
    /// via `rawValue` identity. `1 << 2` is the deprecated `UNNotificationPresentationOptionAlert` (omitted).
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    /// Update the app badge (`1 << 0`).
    public static let badge = Self(rawValue: 1 << 0)
    /// Play a sound (`1 << 1`).
    public static let sound = Self(rawValue: 1 << 1)
    /// Show in the Notification Center list (`1 << 3`).
    public static let list = Self(rawValue: 1 << 3)
    /// Show a banner (`1 << 4`; iOS 14+).
    public static let banner = Self(rawValue: 1 << 4)
}

/// The payload a ``NebulaNotificationsConfiguration/didReceive`` handler gets
/// when the user interacts with a notification.
///
/// All-5 Nebula value (only populated on non-tvOS, where the gated
/// `didReceive` delegate fires). tvOS does not surface notification responses.
public struct NebulaNotificationResponse: Sendable, Equatable, Hashable {

    /// The identifier of the originating request.
    public let identifier: String
    /// The action identifier the user invoked
    /// (`UNNotificationResponse.defaultActionIdentifier` etc.).
    public let actionIdentifier: String

    /// Creates a response value.
    public init(identifier: String, actionIdentifier: String) {
        self.identifier = identifier
        self.actionIdentifier = actionIdentifier
    }
}

/// The authorization options a request to
/// ``NebulaNotificationCenter/requestAuthorization(options:)`` carries.
///
/// A `Sendable` `OptionSet` mirroring the all-5 `UNAuthorizationOptions`
/// raw values (`.badge` / `.sound` / `.alert` / `.providesAppNotificationSettings`
/// / `.provisional` / `.criticalAlert`).
public struct NebulaAuthorizationOptions: OptionSet, Sendable, Equatable, Hashable {

    /// Raw values mirror `UNAuthorizationOptions` so the façade maps via
    /// `rawValue` identity. Note the non-contiguous bit layout (Apple reserves `1 << 3`).
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    /// Update the app badge (`1 << 0`).
    public static let badge = Self(rawValue: 1 << 0)
    /// Play a sound (`1 << 1`).
    public static let sound = Self(rawValue: 1 << 1)
    /// Display an alert (`1 << 2`).
    public static let alert = Self(rawValue: 1 << 2)
    /// Request critical-alert authorization — requires an entitlement (`1 << 4`).
    public static let criticalAlert = Self(rawValue: 1 << 4)
    /// Show an in-app button to notification settings (`1 << 5`).
    public static let providesAppNotificationSettings = Self(rawValue: 1 << 5)
    /// Request provisional (non-interruptive) authorization (`1 << 6`).
    public static let provisional = Self(rawValue: 1 << 6)
}
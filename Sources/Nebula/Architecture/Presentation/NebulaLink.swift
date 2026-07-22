//
//  NebulaLink.swift
//  Nebula
//
//  Wave N21 — External navigation entries conforming to the router. The
//  **normalized external-navigation value**: a `Sendable`/`Equatable`/`Hashable`
//  struct that represents *any* way the app can be asked to navigate somewhere
//  from the outside — a deep link (`myapp://`), a universal link (`https://`),
//  a Spotlight/Handoff/Siri `NSUserActivity`, a Home-screen quick action, a
//  notification tap, or an in-app "go here" that wants to reuse the same path.
//  A bare value type — all four conformances are derived (URL?, String?,
//  [String: String], a frozen `Source` enum — no `@unchecked`). The non-Sendable
//  Apple classes that originate these events (`NSUserActivity` /
//  `UIApplicationShortcutItem` / `UNNotificationResponse`) are NEVER stored here:
//  the adapter (Meridian, or the app's delegate) extracts their **Sendable bits**
//  (urls, type strings, title, a best-effort `[String: String]` payload) and
//  builds a `NebulaLink` at the boundary, so Nebula stays Foundation-only and the
//  link crosses `@Sendable` `Task` closures cleanly. See
//  vault/03-padroes/nebula-deep-links.md.
//

import Foundation

/// A normalized, `Sendable` representation of *any* external navigation event —
/// the value a ``NebulaLinkParser`` resolves into a ``NebulaLinkDestination``.
///
/// Every way the app can be asked to navigate from the outside is funneled
/// through this one value: a **deep link** (`myapp://item/123`), a **universal
/// link** (`https://myapp.com/item/123`), a **Spotlight/Handoff/Siri
/// `NSUserActivity`**, a **Home-screen quick action**, a **notification tap**,
/// or an in-app "go here" that reuses the same parser/router path
/// (``Source/programmatic``). The non-Sendable Apple classes that originate
/// these events are not stored here — the adapter (Meridian, or the app's
/// delegate) extracts their Sendable bits and builds a `NebulaLink` at the
/// boundary, so the link is safe to capture into a `@Sendable` `Task` closure.
///
/// ``init(url:)`` infers the source by scheme: `http`/`https` →
/// ``Source/universalLink``; anything else (incl. a `nil` scheme) →
/// ``Source/urlScheme``. The parser reads the url/query items via
/// `URLComponents` (Foundation) — `NebulaLink` itself carries no parsed
/// structure beyond the raw inputs.
///
/// ```swift
/// // Deep link (custom scheme) — inferred .urlScheme.
/// let deep = NebulaLink(url: URL(string: "myapp://item/\(id)")!)
///
/// // Universal link — inferred .universalLink.
/// let universal = NebulaLink(url: URL(string: "https://myapp.com/item/\(id)")!)
///
/// // Spotlight/Handoff/Siri — built by the Meridian `.meridianUserActivity`
/// // adapter (or the app) from NSUserActivity's Sendable bits.
/// let activity = NebulaLink(source: .userActivity, url: webpageURL,
///                           identifier: activityType, title: title, payload: [:])
/// ```
public struct NebulaLink: Sendable, Equatable, Hashable {

    /// The kind of external event this link originated from.
    public enum Source: Sendable, Equatable, Hashable {
        /// A custom-scheme deep link (`myapp://…`).
        case urlScheme
        /// A universal link (`https://myapp.com/…`) — same `.onOpenURL` entry as
        /// a deep link, distinguished by scheme.
        case universalLink
        /// A Spotlight / Handoff / Siri `NSUserActivity` (arrives via
        /// `.onContinueUserActivity`).
        case userActivity
        /// A Home-screen quick action (`UIApplicationShortcutItem`) —
        /// app-constructed in the delegate (UIKit stays out of Meridian).
        case shortcut
        /// A push/local notification tap (`UNNotificationResponse`) —
        /// app-constructed in the delegate.
        case notification
        /// An in-app "go here" that reuses the same parser/router path as the
        /// external entries (one navigation seam for in-app *and* external).
        case programmatic
    }

    /// The kind of event this link originated from.
    public let source: Source

    /// The URL (a deep link / universal link, or an `NSUserActivity.webpageURL`),
    /// or `nil` for events with no URL (e.g. a shortcut/notification).
    public let url: URL?

    /// An event identifier — a shortcut's `type`, an `NSUserActivity.activityType`,
    /// or a notification's `actionIdentifier`. `nil` when not applicable.
    public let identifier: String?

    /// A human-readable title — an `NSUserActivity`/shortcut title. `nil` when
    /// not applicable.
    public let title: String?

    /// A best-effort `String`-coerced payload — an `NSUserActivity`/shortcut/
    /// notification `userInfo` dictionary, or empty for plain URLs.
    public let payload: [String: String]

    /// Creates a link from its components.
    public init(
        source: Source,
        url: URL? = nil,
        identifier: String? = nil,
        title: String? = nil,
        payload: [String: String] = [:]
    ) {
        self.source = source
        self.url = url
        self.identifier = identifier
        self.title = title
        self.payload = payload
    }

    /// Creates a link from a URL, inferring the source by scheme:
    /// `http`/`https` → ``Source/universalLink``; anything else (including a
    /// `nil` scheme) → ``Source/urlScheme``. `identifier`/`title`/`payload`
    /// default to empty (a plain URL carries no extra metadata).
    public init(url: URL) {
        let scheme = url.scheme?.lowercased()
        if scheme == "http" || scheme == "https" {
            self.source = .universalLink
        } else {
            self.source = .urlScheme
        }
        self.url = url
        self.identifier = nil
        self.title = nil
        self.payload = [:]
    }
}
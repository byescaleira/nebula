//
//  NebulaUNNotificationCenter.swift
//  Nebula
//
//  Wave N15a — App-readiness. The concrete adapter over
// `UNUserNotificationCenter.current()`: a `final class : NSObject` (the
// `UNUserNotificationCenterDelegate` is an `@objc` protocol backed by a `weak`
// Obj-C reference, so a plain Swift class cannot back the delegate — the
// ``NebulaHTTPServer`` `Sendable final class` precedent gains an `NSObject`
// base here) that conforms to ``NebulaNotificationCenter`` (the scheduling
// surface) AND to `UNUserNotificationCenterDelegate` (the callback surface),
// forwarding callbacks to the `@Sendable` handlers in a
// ``NebulaNotificationsConfiguration`` held in a `Mutex`. `Sendable` is derived
// (the only stored property is the `Mutex<Config>`, which is `Sendable`), no
// `@unchecked`. The non-`Sendable` `UNUserNotificationCenter` singleton is
// fetched locally per call (`UNUserNotificationCenter.current()`), never stored
// — it is a shared singleton that cannot be `sending`-consumed (the
// ``NebulaDefaults`` `Mutex<UserDefaults>` + `sending` precedent does not apply).
// See vault/03-padroes/nebula-notifications.md.
//
//  tvOS gating — established precedent: `UNUserNotificationCenterDelegate.didReceive`
// and `UNNotificationResponse` are `API_UNAVAILABLE(tvos)`, and every user-facing
// `UNNotificationContent` property (title/body/subtitle/userInfo) is
// `API_UNAVAILABLE(tvos)`. An `@available(tvOS, unavailable)` DECLARATION gate
// cannot override an already-unavailable protocol requirement ("cannot override
// 'userNotificationCenter' which has been marked unavailable"), and an
// `if #available(...)` RUNTIME check cannot make an `unavailable` symbol compile
// ("'title' is unavailable in tvOS" — the `*` wildcard does NOT exclude tvOS for
// an `unavailable` symbol). The ONLY compile-safe mechanism is `#if !os(tvOS)`
// — a compile gate that excludes the symbol from the tvOS build entirely. N15a
// therefore establishes the `#if !os(<platform>)` precedent for
// platform-`unavailable` SDK symbols (distinct from the `@available(unavailable)`
// declaration gate, which is for declaring a NEBULA symbol unavailable, and from
// the `#if canImport(<framework>)` whole-file gate that N15b establishes for an
// absent framework). On tvOS: the `didReceive` override is absent (the
// requirement is unavailable there) and scheduled notifications are content-less.
//

import Foundation
import UserNotifications
import Synchronization

/// A `final class` adapter over `UNUserNotificationCenter.current()` that
/// conforms to ``NebulaNotificationCenter`` (the scheduling surface) and to
/// `UNUserNotificationCenterDelegate` (the callback surface).
///
/// The façade sets itself as `UNUserNotificationCenter.current().delegate` in
/// ``init(_:)`` and forwards the two delegate callbacks to the `@Sendable`
/// handlers in its ``NebulaNotificationsConfiguration``:
///
/// - `willPresent` (all-5) → ``NebulaNotificationsConfiguration/willPresent``,
///   returning the presentation options synchronously;
/// - `didReceive` (non-tvOS only, gated `#if !os(tvOS)`) →
///   ``NebulaNotificationsConfiguration/didReceive``.
///
/// The `delegate` property is `weak`, so it auto-nils when this instance
/// deallocates — there is no `deinit` (an explicit `delegate = nil` would
/// clobber a replacement façade's delegate). The app's composition root must
/// retain the façade for its lifetime.
///
/// `Sendable` is **derived** (the only stored property is a
/// `Mutex<NebulaNotificationsConfiguration>`, which is `Sendable` because the
/// config is) — no `@unchecked`. The non-`Sendable` `UNUserNotificationCenter`
/// singleton is fetched locally per call, never stored.
public final class NebulaUNNotificationCenter: NSObject, NebulaNotificationCenter, UNUserNotificationCenterDelegate, Sendable {

    /// The callback handlers, held in a `Mutex` so they can be swapped at runtime
    /// (the `~Copyable` `Mutex` is absorbed behind this copyable, `Sendable`
    /// reference — the ``NebulaDefaults`` / ``NebulaLogConfig`` precedent).
    private let mutex: Mutex<NebulaNotificationsConfiguration>

    /// Creates the adapter, installs itself as the shared center's delegate, and
    /// stores the configuration.
    public init(_ config: NebulaNotificationsConfiguration = .default) {
        self.mutex = Mutex(config)
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - NebulaNotificationCenter

    public func requestAuthorization(options: NebulaAuthorizationOptions) async throws -> Bool {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, any Error>) in
            UNUserNotificationCenter.current().requestAuthorization(
                options: UNAuthorizationOptions(rawValue: options.rawValue)
            ) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    public func add(_ request: NebulaNotificationRequest) async throws {
        // A non-positive time interval is rejected by the SDK as an error; fail
        // fast with a precise layer error instead of surfacing the opaque one.
        if case .timeInterval(let ti) = request.trigger, ti <= 0 {
            throw NebulaNotificationsError.invalidTrigger()
        }
        let unRequest = Self.makeUNRequest(request)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            UNUserNotificationCenter.current().add(unRequest) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    public func cancel(_ identifiers: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func cancelAll() async {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    public func pendingRequests() async -> [NebulaNotificationRequest] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[NebulaNotificationRequest], Never>) in
            // Map to Sendable Nebula values INSIDE the SDK completion (where the
            // non-Sendable `UNNotificationRequest` array is delivered), then resume
            // with the Sendable result — resuming with the non-Sendable array
            // directly is a region-isolation error.
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(Self.makeNebulaRequest))
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let config = mutex.withLock { $0 }
        let options = config.willPresent(Self.makeNebulaRequest(notification.request))
        completionHandler(UNNotificationPresentationOptions(rawValue: options.rawValue))
    }

    #if !os(tvOS)
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let config = mutex.withLock { $0 }
        config.didReceive(Self.makeNebulaResponse(response))
        completionHandler()
    }
    #endif

    // MARK: - Mapping (Nebula value <-> UN SDK)
    //
    // The mapping helpers are `internal` (not `private`) so the test module can
    // round-trip through them with constructible `UNNotificationRequest` /
    // `UNMutableNotificationContent` — covering the SDK-mapping logic (including
    // the `#if !os(tvOS)` content path) WITHOUT calling
    // `UNUserNotificationCenter.current()`, which traps in a headless test bundle
    // (no app context). Pure functions; no risk exposing them internally.

    /// Builds a `UNNotificationRequest` from a Nebula request.
    static func makeUNRequest(_ request: NebulaNotificationRequest) -> UNNotificationRequest {
        UNNotificationRequest(
            identifier: request.identifier,
            content: makeUNContent(request.content),
            trigger: makeUNTrigger(request.trigger)
        )
    }

    /// Builds a `UNMutableNotificationContent`. The user-facing properties are
    /// `API_UNAVAILABLE(tvos)` — the assignments are gated `#if !os(tvOS)`, so on
    /// tvOS the request carries a content-less `UNMutableNotificationContent`.
    static func makeUNContent(_ content: NebulaNotificationContent) -> UNMutableNotificationContent {
        let unContent = UNMutableNotificationContent()
        #if !os(tvOS)
        unContent.title = content.title
        unContent.subtitle = content.subtitle
        unContent.body = content.body
        unContent.userInfo = content.userInfo
        #endif
        return unContent
    }

    /// Builds a `UNNotificationTrigger` from a Nebula trigger (or `nil`).
    static func makeUNTrigger(_ trigger: NebulaNotificationTrigger?) -> UNNotificationTrigger? {
        switch trigger {
        case nil:
            return nil
        case .timeInterval(let ti):
            return UNTimeIntervalNotificationTrigger(timeInterval: ti, repeats: false)
        case .calendar(let components):
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }
    }

    /// Maps a `UNNotificationRequest` to a Nebula request.
    static func makeNebulaRequest(_ request: UNNotificationRequest) -> NebulaNotificationRequest {
        NebulaNotificationRequest(
            identifier: request.identifier,
            content: makeNebulaContent(request.content),
            trigger: makeNebulaTrigger(request.trigger)
        )
    }

    /// Maps a `UNNotificationContent` to a Nebula content value. The
    /// user-facing properties are `API_UNAVAILABLE(tvos)` — on tvOS this returns
    /// an empty content value.
    static func makeNebulaContent(_ content: UNNotificationContent) -> NebulaNotificationContent {
        #if os(tvOS)
        return NebulaNotificationContent()
        #else
        return NebulaNotificationContent(
            title: content.title,
            subtitle: content.subtitle,
            body: content.body,
            userInfo: (content.userInfo as? [String: String]) ?? [:]
        )
        #endif
    }

    /// Maps a `UNNotificationTrigger` to a Nebula trigger (or `nil` for an
    /// unsupported trigger type — e.g. push or, when shipped, location).
    static func makeNebulaTrigger(_ trigger: UNNotificationTrigger?) -> NebulaNotificationTrigger? {
        guard let trigger else { return nil }
        if let timeInterval = trigger as? UNTimeIntervalNotificationTrigger {
            return .timeInterval(timeInterval.timeInterval)
        }
        if let calendar = trigger as? UNCalendarNotificationTrigger {
            return .calendar(calendar.dateComponents)
        }
        return nil
    }

    #if !os(tvOS)
    /// Maps a `UNNotificationResponse` to a Nebula response. (Not unit-tested —
    /// `UNNotificationResponse` has no public initializer; system-only.)
    static func makeNebulaResponse(_ response: UNNotificationResponse) -> NebulaNotificationResponse {
        NebulaNotificationResponse(
            identifier: response.notification.request.identifier,
            actionIdentifier: response.actionIdentifier
        )
    }
    #endif
}
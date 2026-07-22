//
//  MeridianDeepLinks.swift
//  Meridian
//
//  Wave N21 — External navigation entries conforming to the router. The SwiftUI
//  entry-point adapters that funnel the framework's navigation callbacks into a
//  ``NebulaLinkRouter``:
// - `.meridianDeepLinks(_:)` wires `.onOpenURL` — covers **deep links**
//   (`myapp://`) and **universal links** (`https://`) (both arrive via the
//   same `.onOpenURL`; ``NebulaLink/init(url:)`` infers the source by scheme).
// - `.meridianUserActivity(_:_:)` wires `.onContinueUserActivity` — covers
//   **Spotlight / Handoff / Siri** `NSUserActivity`.
//  Both build a ``NebulaLink`` then `Task { await linkRouter.open(link) }`.
//  `NSUserActivity` is **not Sendable** — the activity modifier builds the
//  ``NebulaLink`` (Sendable) *inside* the perform closure before the `Task`,
//  capturing only the link across the `@Sendable` Task boundary (no
//  `#SendingClosureRisksDataRace`). `.onOpenURL` is clean — `URL` is Sendable.
//  Home-screen shortcuts and notification taps have no SwiftUI View modifier /
//  pull UIKit → the app builds a ``NebulaLink`` in its delegate and calls
//  `linkRouter.open(_:)` directly (documented; Meridian stays UIKit-free). See
//  vault/03-padroes/nebula-deep-links.md.
//

import SwiftUI
import Nebula

extension View {

    /// Handles **deep links** (`myapp://`) and **universal links** (`https://`)
    /// by routing them through `linkRouter` — both arrive via SwiftUI's
    /// `.onOpenURL`; ``NebulaLink/init(url:)`` infers the source by scheme.
    ///
    /// The URL is `Sendable`, so the `Task` that calls ``NebulaLinkRouter/open(_:)``
    /// captures it cleanly. Pair with
    /// ``meridianUserActivity(_:_:)`` for Spotlight/Handoff/Siri, and construct
    /// ``NebulaLink``s directly for shortcuts/notifications (no SwiftUI hook).
    public func meridianDeepLinks<R: NebulaPresentationRouter & Sendable>(
        _ linkRouter: NebulaLinkRouter<R>
    ) -> some View {
        modifier(MeridianDeepLinksModifier(linkRouter: linkRouter))
    }

    /// Handles **Spotlight / Handoff / Siri** `NSUserActivity` (matching
    /// `activityType`) by routing it through `linkRouter`.
    ///
    /// `NSUserActivity` is **not Sendable** — this builds the ``NebulaLink``
    /// (extracting the activity's `activityType`, `title`, `webpageURL`, and a
    /// best-effort `[String: String]` payload) *inside* the perform closure,
    /// before the `Task`, so only the `Sendable` link crosses the `@Sendable`
    /// `Task` boundary.
    public func meridianUserActivity<R: NebulaPresentationRouter & Sendable>(
        _ activityType: String,
        _ linkRouter: NebulaLinkRouter<R>
    ) -> some View {
        modifier(MeridianUserActivityModifier(activityType: activityType, linkRouter: linkRouter))
    }
}

/// The `.onOpenURL` adapter — deep links + universal links.
private struct MeridianDeepLinksModifier<R: NebulaPresentationRouter & Sendable>: ViewModifier {
    let linkRouter: NebulaLinkRouter<R>

    func body(content: Content) -> some View {
        content.onOpenURL { url in
            // URL is Sendable — capture into the Task is clean.
            Task { await linkRouter.open(NebulaLink(url: url)) }
        }
    }
}

/// The `.onContinueUserActivity` adapter — Spotlight / Handoff / Siri.
private struct MeridianUserActivityModifier<R: NebulaPresentationRouter & Sendable>: ViewModifier {
    let activityType: String
    let linkRouter: NebulaLinkRouter<R>

    func body(content: Content) -> some View {
        content.onContinueUserActivity(activityType) { activity in
            // NSUserActivity is NOT Sendable — build the NebulaLink HERE, before
            // the Task, capturing only the Sendable link across the Task
            // boundary (no #SendingClosureRisksDataRace).
            let link = NebulaLink(
                source: .userActivity,
                url: activity.webpageURL,
                identifier: activity.activityType,
                title: activity.title,
                payload: Self.payload(from: activity.userInfo)
            )
            Task { await linkRouter.open(link) }
        }
    }

    /// Best-effort coerces an `NSUserActivity.userInfo` (`[AnyHashable: Any]?`)
    /// to a `Sendable` `[String: String]`.
    private static func payload(from userInfo: [AnyHashable: Any]?) -> [String: String] {
        guard let userInfo else { return [:] }
        return userInfo.reduce(into: [String: String]()) { acc, kv in
            acc[String(describing: kv.key)] = String(describing: kv.value)
        }
    }
}
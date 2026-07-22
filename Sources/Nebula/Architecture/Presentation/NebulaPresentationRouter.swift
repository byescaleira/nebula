//
//  NebulaPresentationRouter.swift
//  Nebula
//
//  Wave N20 — Presentation navigation styles. The **presentation-intent port**:
//  a sub-protocol of ``NebulaRouter`` that adds modal intents (`present`/
//  `dismiss`) on top of the push-only `push`/`pop`/`popToRoot`/`replaceStack`.
//  Additive — existing ``NebulaRouter`` conformers are untouched; adopters opt
//  into the richer port. Requirements are **`async`** for the same reason
//  ``NebulaRouter``'s are: a `@MainActor` `@Observable` concrete `Router` (in
//  Meridian) satisfies this nonisolated, Foundation-only port (the `await` hops
//  to the main actor). Sync concrete impls stay valid — the spy records
//  without async ceremony. See vault/03-padroes/nebula-presentation-architecture.md.
//

import Foundation

/// The presentation-intent port: a sub-protocol of ``NebulaRouter`` adding
/// modal presentation intents.
///
/// Adopts the push-only ``NebulaRouter`` and adds `present(_:)` (dispatch by
/// the route's declared ``NebulaRoute/presentationStyle``), `present(_:as:)`
/// (call-site override), and `dismiss()` (modal → clear; else pop). The modal
/// state is a single slot — one sheet/full-screen cover at a time (matches
/// SwiftUI). Existing ``NebulaRouter`` conformers are **untouched** — adopting
/// the richer port is opt-in (the ``NebulaSpyRouter`` and the Meridian `Router`
/// both adopt it in Wave N20; a push-only conformer stays valid as a
/// `NebulaRouter`).
///
/// Requirements are **`async`** so a `@MainActor @Observable` concrete `Router`
/// (the sibling Meridian package) can satisfy this nonisolated, Foundation-only
/// port — the same rationale as ``NebulaRouter``. Sync concrete impls stay
/// valid (the spy records intents without async ceremony).
///
/// ```swift
/// // In a viewmodel — depends on the richer port, not the concrete Router.
/// func share(_ id: UUID) async { await router.present(.share(id: id)) }
/// func login() async          { await router.present(.login, as: .fullScreenCover) }
/// func done() async           { await router.dismiss() }
/// ```
public protocol NebulaPresentationRouter<Route>: NebulaRouter {

    /// Presents `route` by its declared ``NebulaRoute/presentationStyle`` — a
    /// `.push` route pushes onto the stack; a `.sheet`/`.fullScreenCover`
    /// route is presented modally.
    func present(_ route: Route) async

    /// Presents `route` as `style`, overriding the route's declared style at
    /// the call site.
    func present(_ route: Route, as style: NebulaPresentationStyle) async

    /// Dismisses the active modal if one is present; otherwise pops one route
    /// from the stack. Never both.
    func dismiss() async
}

// MARK: External navigation entries (Wave N21)

extension NebulaPresentationRouter {

    /// Applies a resolved ``NebulaLinkDestination`` to this router — the single
    /// source of truth for translating an external navigation entry (deep link,
    /// universal link, UserActivity, shortcut, notification, or programmatic)
    /// into router intents.
    ///
    /// Stack-rebuild cases (``NebulaLinkDestination/pushStack(_:)`` and
    /// ``NebulaLinkDestination/pushStackAndPresent(_:_:)`) call `dismiss()`
    /// **first** to clear any stale modal — `replaceStack(with:)` does not touch
    /// the modal slot, so without this a sheet/cover left open would persist over
    /// the freshly rebuilt stack. The `dismiss()` is harmless when no modal is
    /// active (it pops one, but that pop is immediately erased by the
    /// `replaceStack` that follows). ``NebulaLinkDestination/present(_:)` and
    /// ``NebulaLinkDestination/dismiss`` do **not** dismiss first — their
    /// semantics are additive over the current state.
    ///
    /// This is a **default extension method**, not a protocol requirement —
    /// conformers (``NebulaSpyRouter``, the Meridian `Router`, any app router)
    /// inherit it automatically; adopting it is opt-in and additive. The
    /// ``NebulaLinkRouter`` delegates here, so the destination→intents
    /// translation lives once.
    ///
    /// ```swift
    /// // A deep-link handler resolves a link, then applies the destination.
    /// await router.apply(parser.resolve(link))
    /// ```
    public func apply(_ destination: NebulaLinkDestination<Route>) async {
        switch destination {
        case .unhandled:
            break
        case .present(let route):
            await present(route)
        case .pushStack(let routes):
            await dismiss()
            await replaceStack(with: routes)
        case .pushStackAndPresent(let routes, let modal):
            await dismiss()
            await replaceStack(with: routes)
            await present(modal)
        case .dismiss:
            await dismiss()
        }
    }
}
//
//  NebulaLinkDestination.swift
//  Nebula
//
//  Wave N21 — External navigation entries conforming to the router. The
//  **resolved destination** of a ``NebulaLink``: what a ``NebulaLinkParser``
//  returns, and what ``NebulaPresentationRouter/apply(_:)`` translates into
//  router intents. A bare `Sendable`/`Equatable` enum generic over
//  `Route: NebulaRoute` (both derived — `Route` is `Sendable`/`Equatable` via
//  `NebulaRoute`). The case named `unhandled` (not `none`) sidesteps an
//  `Optional.none` ambiguity at the call site. See
//  vault/03-padroes/nebula-deep-links.md.
//

import Foundation

/// What a ``NebulaLinkParser`` resolves a ``NebulaLink`` to — the navigation
/// intent the router should enact.
///
/// The five cases cover every practical deep-link shape:
///
/// - ``unhandled`` — the parser did not recognize the link; the router does
///   nothing (a composite parser moves on to the next parser).
/// - ``present(_:)`` — present a single route, dispatched by its declared
///   ``NebulaRoute/presentationStyle`` (a `.push` route pushes; a `.sheet`/
///   `.fullScreenCover` route fills the modal slot).
/// - ``pushStack(_:)`` — **rebuild** the push path (the deep-link primitive):
///   `replaceStack(with:)`. Any stale modal is cleared first (see
///   ``NebulaPresentationRouter/apply(_:)``).
/// - ``pushStackAndPresent(_:_)`` — rebuild the path *and* present a route over
///   it (e.g. `myapp://item/123/share` → push to item 123, then sheet its
///   share). The second route is dispatched by its own `presentationStyle`.
/// - ``dismiss`` — close the current modal (or pop one) — a "close" intent.
///
/// `Sendable`/`Equatable` are derived (`Route: NebulaRoute` supplies both).
/// The case is `unhandled` (not `none`) so an `Optional<NebulaLinkDestination>`
/// does not clash with `Optional.none`.
public enum NebulaLinkDestination<Route: NebulaRoute>: Sendable, Equatable {

    /// The parser did not recognize the link — the router does nothing.
    case unhandled

    /// Present `route`, dispatched by its declared
    /// ``NebulaRoute/presentationStyle``.
    case present(Route)

    /// Rebuild the push path with `routes` (the deep-link primitive). Any stale
    /// modal is cleared first.
    case pushStack([Route])

    /// Rebuild the push path with `routes`, then present `modal` over it (the
    /// "deep link into a screen, then open its sheet/cover" compound). `modal`
    /// is dispatched by its own `presentationStyle`.
    case pushStackAndPresent([Route], Route)

    /// Dismiss the active modal (or pop one if none is active) — a "close"
    /// intent.
    case dismiss
}
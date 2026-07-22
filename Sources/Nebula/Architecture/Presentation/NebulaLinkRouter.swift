//
//  NebulaLinkRouter.swift
//  Nebula
//
//  Wave N21 — External navigation entries conforming to the router. The
//  **glue**: composes a ``NebulaPresentationRouter`` with a ``NebulaLinkParser``
//  and exposes a single `open(_:)` entry — parse the link, then
//  `await router.apply(destination)`. A `Sendable` struct (both `let` props are
//  `Sendable` — `Router: NebulaPresentationRouter & Sendable`, and
//  `any NebulaLinkParser<Route>` is `Sendable` since `NebulaLinkParser: Sendable`;
//  no `@unchecked`), so it can be captured into the `@Sendable` `Task` closures
//  the Meridian `.onOpenURL`/`.onContinueUserActivity` adapters create.
//  `open(_:)` is nonisolated `async` — `await router.apply(...)` hops to the
//  Meridian `Router`'s `@MainActor` (sync methods witnessing the async
//  requirements, per ``NebulaRouter``). The destination→intents translation
//  lives once in ``NebulaPresentationRouter/apply(_:)``; `open` is a one-liner.
//  See vault/03-padroes/nebula-deep-links.md.
//

import Foundation

/// The glue that funnels a ``NebulaLink`` through a ``NebulaLinkParser`` into a
/// ``NebulaPresentationRouter``.
///
/// Composes a router with a parser and exposes one entry point —
/// ``open(_:)`` — which resolves the link and applies the resulting
/// ``NebulaLinkDestination`` to the router. The destination→intents
/// translation lives once in ``NebulaPresentationRouter/apply(_:)`` (an
/// additive default extension); `open` delegates to it, so the spy and the
/// Meridian `Router` both get the semantics for free.
///
/// `Sendable` (both stored `let` props are `Sendable`), so it is safe to capture
/// into the `@Sendable` `Task` closures the Meridian `.onOpenURL` /
/// `.onContinueUserActivity` adapters create. `open(_:)` is nonisolated
/// `async` — `await router.apply(...)` hops to the Meridian `Router`'s
/// `@MainActor` (a sync `@MainActor` method witnessing an async requirement,
/// per ``NebulaRouter``); Nebula stays `@MainActor`-free.
///
/// The parser is held **existentially** (`any NebulaLinkParser<Router.Route>`)
/// — one generic parameter, a runtime-swappable parser, negligible existential
/// cost for synchronous URL parsing.
///
/// ```swift
/// let linkRouter = NebulaLinkRouter(
///     router: tabRouter,
///     parser: NebulaCompositeLinkParser([SchemeLinkParser(), UniversalLinkParser()])
/// )
/// // Meridian: `.meridianDeepLinks(linkRouter)` wires `.onOpenURL` → `open`.
/// ```
public struct NebulaLinkRouter<Router: NebulaPresentationRouter & Sendable>: Sendable {

    /// The presentation router the resolved destinations drive.
    public let router: Router

    /// The link parser that resolves ``NebulaLink``s into destinations.
    public let parser: any NebulaLinkParser<Router.Route>

    /// Creates a link router from `router` and `parser`.
    public init(router: Router, parser: any NebulaLinkParser<Router.Route>) {
        self.router = router
        self.parser = parser
    }

    /// Resolves `link` via the parser and applies the resulting destination to
    /// the router. A `.unhandled` result is a no-op.
    public func open(_ link: NebulaLink) async {
        await router.apply(parser.resolve(link))
    }
}
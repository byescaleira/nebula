//
//  NebulaRouter.swift
//  Nebula
//
//  Wave I — Presentation architecture (Foundation-only seams). The **navigation
//  intent port**: the seam an outer adapter (a viewmodel, a deep-link handler)
//  calls to mutate navigation without knowing how routes render. A `Sendable`
//  protocol with a primary associated type `Route: NebulaRoute` (SE-0346) so it
//  can be used as `any NebulaRouter<AppRoute>` or `some NebulaRouter<AppRoute>`.
//  Requirements are **`async`** — this is the Swift 6 way to let a `@MainActor`
//  `@Observable` concrete `Router` (in Meridian) satisfy a nonisolated,
//  Foundation-only port: a synchronous `@MainActor` method witnesses a
//  nonisolated `async` requirement (the `await` performs the actor hop), so
//  Nebula stays free of `@MainActor` (the app supplies isolation) yet the
//  on-actor router conforms. The async port is also the **cross-actor bridge**:
//  an off-actor deep-link parser can `await router.replaceStack(with:)` to drive
//  the on-actor router. Conformers may keep **synchronous** implementations — a
//  sync method witnesses an async requirement (no hop for a nonisolated sync
//  impl, an actor hop for an isolated one) — so concrete calls stay sync and
//  the ``NebulaSpyRouter`` test double records without async ceremony. See
//  vault/03-padroes/nebula-presentation-architecture.md.
//

import Foundation

/// The navigation-intent port: mutate navigation by **intent** without knowing
/// how routes render.
///
/// A `Sendable` protocol with a primary associated type `Route: NebulaRoute`
/// (SE-0346), usable as `any NebulaRouter<AppRoute>` (existential) or
/// `some NebulaRouter<AppRoute>` (opaque). Requirements are **`async`** so a
/// `@MainActor` `@Observable` concrete `Router` (the sibling Meridian package)
/// can satisfy this nonisolated, Foundation-only port — a synchronous
/// `@MainActor` method witnesses a nonisolated `async` requirement (the `await`
/// hops to the main actor). This keeps Nebula free of `@MainActor` (an app
/// consuming Nebula supplies its own isolation) while still letting the on-actor
/// router conform. The async port doubles as the **cross-actor bridge**: an
/// off-actor deep-link parser can `await router.replaceStack(with:)` to drive
/// the on-actor router.
///
/// Conformers may keep **synchronous** implementations — a sync method witnesses
/// an async requirement (the compiler synthesizes the async wrapper; no hop for
/// a nonisolated sync impl, an actor hop for an isolated one) — so concrete calls
/// stay synchronous and the ``NebulaSpyRouter`` test double records intents
/// without async ceremony. The viewmodel holds a router via **constructor
/// injection** and calls intent methods; it never knows how a `Route` becomes a
/// `View`. Substitute a ``NebulaSpyRouter`` in tests.
///
/// ```swift
/// // In a viewmodel (Meridian/app) — depends on the port, not the concrete.
/// func openDetail(_ id: UUID) async {
///     await router.push(.detail(id: id))
/// }
/// func goBack() async {
///     await router.pop()
/// }
/// func handleDeepLink(_ routes: [AppRoute]) async {
///     await router.replaceStack(with: routes)
/// }
/// ```
public protocol NebulaRouter<Route>: Sendable {
    /// The route type this router navigates.
    associatedtype Route: NebulaRoute

    /// Pushes `route` onto the top of the stack.
    func push(_ route: Route) async

    /// Pops a single route off the top.
    func pop() async

    /// Pops `count` routes off the top (clamped by the implementation; never
    /// underflows).
    func pop(_ count: Int) async

    /// Pops every route — back to root.
    func popToRoot() async

    /// Replaces the whole stack with `routes` — the deep-link primitive.
    func replaceStack(with routes: [Route]) async
}
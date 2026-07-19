//
//  Router.swift
//  Meridian
//
//  Wave II — The presentation-architecture `@Observable Router` that renders
//  Nebula's Foundation-only navigation model. A `@MainActor @Observable final
//  class` generic over `Route: NebulaRoute`, conforming to `NebulaRouter<Route>`
//  (the Foundation-only intent port). Navigation state is owned here, NOT in the
//  viewmodel — the data-driven Router pattern (no Coordinator tree; owner
//  preference). The stack logic itself lives in Nebula's
//  `NebulaNavigationStack` static helpers — this Router delegates to them so
//  the pure-Swift model and the observable wrapper share one implementation
//  (no duplication). `Sendable` by `@MainActor` isolation (a `@MainActor
//  @Observable final class` is Sendable for free), satisfying `NebulaRouter`'s
//  `Sendable` requirement. Bindable for `NavigationStack(path: $router.path)`.
//  See vault/03-padroes/nebula-presentation-architecture.md.
//

import SwiftUI
import Nebula

/// The data-driven navigation `Router` — an `@Observable` owner of a typed
/// `[Route]` stack per tab/flow.
///
/// One `Router` per tab (never share a path across tabs). Views call
/// `router.push(.detail(id:))` with zero knowledge of destination views; the
/// viewmodel takes the router via constructor injection (substitute a
/// `NebulaSpyRouter` in tests). Deep links are "build `[Route]`,
/// `router.replaceStack(with:)`". `Codable` `Route` + the `path` array give
/// state restoration for free.
///
/// This is the **Router** pattern, not a Coordinator tree (owner preference):
/// no `AppCoordinator`/`AuthCoordinator` object hierarchy, no
/// `@ViewBuilder`-returning coordinator, no `@Environment`-injected coordinator.
/// A genuinely nested/reused flow is a typed `[Route]` sub-stack owned by a
/// feature `Router`, not a coordinator object.
///
/// ```swift
//   @MainActor @Observable
//   final class ProfileViewModel: NebulaViewModel {
//       let router: Router<AppRoute>
//       init(router: Router<AppRoute>) { self.router = router }
//       func openDetail(_ id: UUID) { router.push(.detail(id: id)) }
//   }
//
//   // Root view — one NavigationStack per tab.
//   MeridianNavigationStack(router: router) {
//       RootView()
//   } destination: { route in
//       switch route {
//       case .detail(let id): DetailView(id: id)
//       case .settings:       SettingsView()
//       }
//   }
//   ```
@MainActor @Observable public final class Router<Route: NebulaRoute>: NebulaRouter<Route> {

    /// The typed route stack, root-first. Tracked by Observation — mutating it
    /// (directly or through the intent methods) notifies observing views. Bind
    /// with `$router.path` into `NavigationStack(path:)`.
    public var path: [Route] = []

    /// Creates a router with `path` (defaulting to empty — at root).
    public init(path: [Route] = []) {
        self.path = path
    }

    // MARK: NebulaRouter<Route> — delegates to NebulaNavigationStack statics
    // (single source of truth for stack mutation; the pure-Swift model and this
    // observable wrapper share one implementation).

    public func push(_ route: Route) {
        NebulaNavigationStack.push(route, into: &path)
    }

    public func pop() {
        NebulaNavigationStack.pop(1, into: &path)
    }

    public func pop(_ count: Int) {
        NebulaNavigationStack.pop(count, into: &path)
    }

    public func popToRoot() {
        NebulaNavigationStack.popToRoot(&path)
    }

    public func replaceStack(with routes: [Route]) {
        NebulaNavigationStack.replaceStack(routes, into: &path)
    }

    // MARK: Read-only accessors (convenience; mirror NebulaNavigationStack).

    /// The number of routes above root.
    public var count: Int { path.count }

    /// `true` when at root.
    public var isEmpty: Bool { path.isEmpty }

    /// The top route, or `nil` at root.
    public var top: Route? { path.last }
}
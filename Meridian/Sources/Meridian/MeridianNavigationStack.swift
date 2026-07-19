//
//  MeridianNavigationStack.swift
//  Meridian
//
//  Wave II — The SwiftUI wiring that renders Nebula's typed `[Route]` model.
//  `NavigationStack(path: $router.path)` + `navigationDestination(for: Route.self)`
//  with a `@ViewBuilder` destination resolver — the type-driven view factory. The
//  `switch route` the caller writes is compile-time exhaustive (typed `[Route]`
//  over type-erased `NavigationPath`), and pushing identifier values keeps the
//  stack cheap and `Codable`. One `MeridianNavigationStack` per tab. See
//  vault/03-padroes/nebula-presentation-architecture.md.
//

import SwiftUI
import Nebula

/// A `NavigationStack` bound to a ``Router``'s typed `[Route]` path, with a
/// type-driven `@ViewBuilder` destination resolver.
///
/// The thin SwiftUI adapter over Nebula's navigation model: `NavigationStack`
/// reads `$router.path`, and `navigationDestination(for: Route.self)` resolves
/// each `Route` to a destination view via the `switch route` the caller writes.
/// Push identifier values (`.detail(id:)`), not full models — destination views
/// load their own data from the identifier.
///
/// ```swift
/// MeridianNavigationStack(router: tabRouter) {
///     RootView()
/// } destination: { route in
///     switch route {
///     case .detail(let id): DetailView(id: id)
///     case .settings:       SettingsView()
///     case .editItem(let id): EditItemView(id: id)
///     }
/// }
/// ```
///
/// One `MeridianNavigationStack` per tab — never share a `Router`/path across
/// tabs (a SwiftUI navigation footgun). For modals/sheets/alerts, model each
/// feature's destination as a single `Optional<Destination>` enum driving
/// `sheet(item:)`/`alert(item:)` ("impossible states unrepresentable" — the
/// type-driven enum-destination pattern, Wave III).
public struct MeridianNavigationStack<Route: NebulaRoute, Root: View, Destination: View>: View {

    @MainActor private let router: Router<Route>
    @ViewBuilder private let root: () -> Root
    @ViewBuilder private let destination: (Route) -> Destination

    /// Creates a stack bound to `router`, rendering `root` at the root and
    /// `destination(route)` for each pushed `Route`.
    public init(
        router: Router<Route>,
        @ViewBuilder root: @escaping () -> Root,
        @ViewBuilder destination: @escaping (Route) -> Destination
    ) {
        self.router = router
        self.root = root
        self.destination = destination
    }

    public var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            root()
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                }
        }
    }
}
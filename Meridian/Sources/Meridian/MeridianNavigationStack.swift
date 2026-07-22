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
/// tabs (a SwiftUI navigation footgun).
///
/// Modals (Wave N20): the same `destination` resolver drives `.sheet`/
/// `.fullScreenCover` from the router's single modal slot. A route's declared
/// ``NebulaRoute/presentationStyle`` (or a `present(_:as:)` override) decides
/// whether `router.present(route)` pushes onto `path` or fills `presented`/
/// `presentedStyle` — and this view presents the modal via the matching
/// `isPresented` binding. Use `.sheet(isPresented:)`/`.fullScreenCover(
/// isPresented:)` (not `.sheet(item:)`) so `Route` need not be `Identifiable`.
/// Only one modal is active at a time (single slot); setting the binding back
/// to `false` calls `router.dismiss()`.
public struct MeridianNavigationStack<Route: NebulaRoute, Root: View, Destination: View>: View {

    @MainActor private let router: Router<Route>
    @ViewBuilder private let root: () -> Root
    @ViewBuilder private let destination: (Route) -> Destination

    /// Creates a stack bound to `router`, rendering `root` at the root and
    /// `destination(route)` for each pushed `Route` and each presented modal
    /// (`sheet`/`fullScreenCover`).
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
        .sheet(isPresented: Binding(
            get: {
                guard router.presented != nil else { return false }
                #if os(macOS)
                // `fullScreenCover` is unavailable on macOS; a `.fullScreenCover`
                // route falls back to a sheet there (graceful — macOS has no
                // full-screen cover surface).
                return router.presentedStyle == .sheet
                    || router.presentedStyle == .fullScreenCover
                #else
                return router.presentedStyle == .sheet
                #endif
            },
            set: { if !$0 { router.dismiss() } }
        )) {
            if let route = router.presented {
                destination(route)
            }
        }
        #if !os(macOS)
        .fullScreenCover(isPresented: Binding(
            get: { router.presented != nil && router.presentedStyle == .fullScreenCover },
            set: { if !$0 { router.dismiss() } }
        )) {
            if let route = router.presented {
                destination(route)
            }
        }
        #endif
    }
}
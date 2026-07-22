//
//  MeridianNavigationSplitView.swift
//  Meridian
//
//  Wave N20 — The SwiftUI split-container adapter. `NavigationSplitView` with a
//  sidebar + a detail column that is a ``MeridianNavigationStack`` (push + modal
//  reuse — one `Router` per column, the "one Router per flow" rule). The
//  sidebar is owner-supplied (a `List` with `NavigationLink(value:)` typically);
//  the detail renders `detailRoot` at its root and `destination(route)` for each
//  pushed/presented `Route`. `NavigationSplitView` subsumes the deprecated
//  `NavigationView` (deprecated since iOS 16) — the modern split container at
//  the `.v26` floor (iOS 16/macOS 13, no `@available` gate). See
//  vault/03-padroes/nebula-presentation-architecture.md.
//

import SwiftUI
import Nebula

/// A `NavigationSplitView` with an owner-supplied sidebar and a detail column
/// backed by a ``MeridianNavigationStack``.
///
/// The split container for two-column layouts (iPad/macOS sidebar + detail).
/// The detail column is a full ``MeridianNavigationStack`` — it pushes
/// `Route`s onto `detailRouter.path`, presents modals from
/// `detailRouter.presented`, and resolves destinations through `destination`
/// — so a split view inherits the same data-driven Router pattern as a stack,
/// with its own `Router` (never share a `Router`/path across columns). The
/// sidebar is owner-supplied; push from it with `NavigationLink(value:)`
/// against `detailRouter`.
///
/// `NavigationSplitView` replaces the deprecated `NavigationView` (deprecated
/// since iOS 16) — the modern trio at `.v26` is `NavigationStack` +
/// `NavigationSplitView` + `TabView`.
///
/// ```swift
/// MeridianNavigationSplitView(sidebar: {
///     List(selection: $selection) { ItemRow(item: $0) }
///         .navigationTitle("Items")
/// }, detailRouter: detailRouter, detailRoot: {
///     DetailRootView()
/// }, destination: { route in
///     switch route {
///     case .detail(let id): DetailView(id: id)
///     case .settings:       SettingsView()
///     }
/// })
/// ```
public struct MeridianNavigationSplitView<
    Route: NebulaRoute,
    Sidebar: View,
    DetailRoot: View,
    Destination: View
>: View {

    @MainActor private let detailRouter: Router<Route>
    @ViewBuilder private let sidebar: () -> Sidebar
    @ViewBuilder private let detailRoot: () -> DetailRoot
    @ViewBuilder private let destination: (Route) -> Destination

    /// Creates a split view with an owner-supplied `sidebar` and a detail
    /// column bound to `detailRouter` (rendering `detailRoot` at its root and
    /// `destination(route)` for each pushed/presented `Route`).
    public init(
        sidebar: @escaping () -> Sidebar,
        detailRouter: Router<Route>,
        @ViewBuilder detailRoot: @escaping () -> DetailRoot,
        @ViewBuilder destination: @escaping (Route) -> Destination
    ) {
        self.sidebar = sidebar
        self.detailRouter = detailRouter
        self.detailRoot = detailRoot
        self.destination = destination
    }

    public var body: some View {
        NavigationSplitView {
            sidebar()
        } detail: {
            MeridianNavigationStack(router: detailRouter, root: detailRoot,
                                    destination: destination)
        }
    }
}
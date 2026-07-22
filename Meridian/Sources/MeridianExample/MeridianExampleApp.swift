//
//  MeridianExampleApp.swift
//  MeridianExample
//
//  Wave N20/N21 — a runnable demonstration of the full data-driven Router
//  pattern with the modern container trio, per-route presentation styles, and
//  **external navigation entries conforming to the router**:
//  - `MeridianTabView` root (one `Router` per tab — never share a path),
//  - `MeridianNavigationSplitView` in the items tab (sidebar + detail stack),
//  - `MeridianNavigationStack` in the settings tab,
//  - per-route `presentationStyle`: `.share(id:)` → `.sheet`, `.login` →
//    `.fullScreenCover` (on macOS the cover falls back to a sheet — the
//    adapter gates `fullScreenCover` to non-macOS),
//  - `present(_:)` dispatches by declared style; `present(_:as:)` overrides,
//  - **Wave N21** — deep links + universal links (`.meridianDeepLinks` via
//    `.onOpenURL`) and Spotlight/Handoff/Siri (`.meridianUserActivity` via
//    `.onContinueUserActivity`) are funneled through an `AppLinkParser:
//    NebulaLinkParser` → `NebulaLinkRouter` → the bound `Router`. An in-app
//    button opens a URL via `@Environment(\.openURL)` to exercise the path;
//    shortcuts/notifications would build a `NebulaLink` in a delegate (not
//    shown — Meridian stays UIKit-free).
//  Living docs for the presentation architecture; not a shipped product.
//  Compiling it is the Wave N21 gate; `swift run MeridianExample` launches the
//  macOS app.

import SwiftUI
import Nebula
import Meridian

// MARK: - Routes (NebulaRoute — push identifier values, render models)

enum AppRoute: NebulaRoute {
    case root
    case detail(id: UUID)
    case settings
    case share(id: UUID)   // sheet
    case login             // full-screen cover

    /// Per-route presentation style — the Wave N20 dispatch key. `.share` is a
    /// sheet; `.login` is a full-screen cover; everything else pushes.
    var presentationStyle: NebulaPresentationStyle {
        switch self {
        case .share:      return .sheet
        case .login:      return .fullScreenCover
        default:          return .push
        }
    }
}

// MARK: - Tabs (one Router per tab — never share a path across tabs)

enum AppTab: CaseIterable, Hashable, Sendable {
    case items
    case settings
}

// MARK: - External navigation entries (NebulaLinkParser — link → destination)
//
// Wave N21: every external entry — deep links (`nebula://`), universal links
// (`https://`), Spotlight/Handoff/Siri — is normalized to a `NebulaLink` and
// resolved here into a `NebulaLinkDestination`, then `apply`-ed to the router.
// Replaces the Wave III ad-hoc `URL → [Route]` function with the proper port.

struct AppLinkParser: NebulaLinkParser {
    typealias Route = AppRoute

    func resolve(_ link: NebulaLink) -> NebulaLinkDestination<AppRoute> {
        guard let url = link.url,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return .unhandled }

        var routes: [AppRoute] = [.root]
        for segment in comps.path.split(separator: "/").map(String.init) {
            switch segment {
            case "settings":
                routes.append(.settings)
            case "login":
                // Present the full-screen cover directly (the route's declared
                // style is `.fullScreenCover`).
                return .present(.login)
            default:
                if let id = UUID(uuidString: segment) {
                    routes.append(.detail(id: id))
                }
            }
        }
        // Only recognized segments beyond root rebuild the stack; an
        // unrecognized URL is `.unhandled` (the router is left untouched).
        return routes.count > 1 ? .pushStack(routes) : .unhandled
    }
}

// MARK: - A viewmodel (@MainActor @Observable, NebulaViewModel marker)

@MainActor @Observable
final class ItemListViewModel: NebulaViewModel {
    let router: Router<AppRoute>

    init(router: Router<AppRoute>) { self.router = router }

    func openDetail(_ id: UUID) { router.push(.detail(id: id)) }

    // Dispatch by the route's declared style → .share presents as a sheet.
    func share(_ id: UUID) { router.present(.share(id: id)) }

    // Call-site override: present .login (declared .fullScreenCover) — shown
    // here explicitly for the demo. `present(_:as:)` overrides the declared
    // style (e.g. `router.present(.settings, as: .sheet)` would sheet a route
    // that otherwise pushes).
    func login() { router.present(.login, as: .fullScreenCover) }

    func dismiss() { router.dismiss() }
}

// MARK: - App

@main
struct MeridianExampleApp: App {
    // One Router per tab — never share a path across tabs.
    @State private var itemsRouter = Router<AppRoute>()
    @State private var settingsRouter = Router<AppRoute>()

    /// Deep links + universal links (`nebula://`, `https://`) and
    /// Spotlight/Handoff/Siri, funneled through the same `NebulaLinkRouter` →
    /// the items `Router` (Wave N21). One `NebulaLink` normalization, one
    /// `AppLinkParser`, one router — every external entry conforms to it.
    private var itemsLinkRouter: NebulaLinkRouter<Router<AppRoute>> {
        NebulaLinkRouter(router: itemsRouter, parser: AppLinkParser())
    }

    var body: some Scene {
        WindowGroup {
            MeridianTabView(selection: AppTab.items) { tab in
                switch tab {
                case .items:    itemsTab
                case .settings: settingsTab
                }
            }
            .meridianDeepLinks(itemsLinkRouter)
            .meridianUserActivity("com.byescaleira.nebula.item", itemsLinkRouter)
        }
    }

    /// The items tab — a split container (sidebar + detail stack). Erased to
    /// `AnyView` so `MeridianTabView`'s `Content` is a single concrete type
    /// (the `@ViewBuilder` switch of two distinct container view types trips a
    /// known type-inference fragility in this demo closure — erasure here is
    /// demo-only, never shipped library API).
    private var itemsTab: AnyView {
        AnyView(MeridianNavigationSplitView(sidebar: {
            SidebarView(router: itemsRouter)
        }, detailRouter: itemsRouter, detailRoot: {
            ItemsRootView(vm: ItemListViewModel(router: itemsRouter))
        }, destination: { route in
            DestinationView(route: route)
        }))
    }

    /// The settings tab — a plain stack (erased to `AnyView`; see `itemsTab`).
    private var settingsTab: AnyView {
        AnyView(MeridianNavigationStack(router: settingsRouter) {
            SettingsRootView()
        } destination: { route in
            DestinationView(route: route)
        })
    }
}

// MARK: - Views (pure functions of state)

private struct SidebarView: View {
    @MainActor let router: Router<AppRoute>

    var body: some View {
        List {
            NavigationLink("Settings", value: AppRoute.settings)
            NavigationLink("Detail", value: AppRoute.detail(id: UUID()))
        }
        .navigationTitle("Items")
        // A route declared .sheet presented from the sidebar.
        Button("Share") { router.present(.share(id: UUID())) }
    }
}

private struct ItemsRootView: View {
    @MainActor let vm: ItemListViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack {
            Text("Items root")
            Button("Open detail") { vm.openDetail(UUID()) }
            Button("Share (sheet)") { vm.share(UUID()) }
            Button("Login (cover)") { vm.login() }
            // Exercises the deep-link path from within the app: opens a URL that
            // `.meridianDeepLinks` funnels through `AppLinkParser` → the router.
            Button("Open via deep link (settings)") {
                openURL(URL(string: "nebula://app/settings")!)
            }
            Button("Open via deep link (login)") {
                openURL(URL(string: "nebula://app/login")!)
            }
        }
        .navigationTitle("Items")
    }
}

private struct SettingsRootView: View {
    var body: some View {
        Text("Settings root")
            .navigationTitle("Settings")
    }
}

private struct DestinationView: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .root:
            Text("Root")
        case .detail(let id):
            VStack {
                Text("Detail \(id.uuidString.prefix(8))")
                Button("Share this (sheet)") {
                    // Routed through the bound Router would be ideal; the demo
                    // resolves the destination view only.
                }
            }
            .navigationTitle("Detail")
        case .settings:
            Text("Settings")
                .navigationTitle("Settings")
        case .share(let id):
            VStack {
                Text("Share sheet for \(id.uuidString.prefix(8))")
                Button("Done") {
                    // The sheet/cover binding calls router.dismiss() on swipe;
                    // a Done button would call the same — omitted for brevity.
                }
            }
            .presentationDetents([.medium])
        case .login:
            VStack { Text("Login (full-screen cover)") }
        }
    }
}
//
//  MeridianExampleApp.swift
//  MeridianExample
//
//  Wave III — a runnable demonstration of the full data-driven Router pattern:
//  `Router` + a typed `[Route]` (`AppRoute`) + `MeridianNavigationStack` + a
//  type-driven `Destination` enum driving `sheet(item:)` ("impossible states
//  unrepresentable" — only one destination active, compiler-enforced) + a
//  deep-link handler (`onOpenURL` → parse → `replaceStack`). Living docs for the
//  presentation architecture; not a shipped product. Compiling it is the Wave
//  III gate; `swift run MeridianExample` launches the macOS app.
//

import SwiftUI
import Nebula
import Meridian

// MARK: - Routes (NebulaRoute — push identifier values, render models)

enum AppRoute: NebulaRoute {
    case root
    case detail(id: UUID)
    case settings
}

// MARK: - Deep link (parse URL → [AppRoute]) — deep-link-as-data

enum DeepLink {
    // `nebula://<host>/detail/<uuid>` / `nebula://<host>/settings` → a `[AppRoute]`.
    static func parse(_ url: URL) -> [AppRoute] {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return [.root]
        }
        var routes: [AppRoute] = [.root]
        for segment in comps.path.split(separator: "/").map(String.init) {
            switch segment {
            case "settings":
                routes.append(.settings)
            default:
                if let id = UUID(uuidString: segment) {
                    routes.append(.detail(id: id))
                }
            }
        }
        return routes
    }
}

// MARK: - Type-driven destinations (modals — one active, compiler-enforced)

// A single optional enum drives `sheet(item:)` — only one destination is active
// at a time, so "showing the edit sheet AND the delete alert" is unrepresentable.
// `Identifiable` is hand-rolled (no `@CasePathable` macro — `dependencies: []`).
enum Destination: Identifiable {
    case editItem(UUID)
    case confirmDelete(UUID)

    var id: String {
        switch self {
        case .editItem(let id):       "edit-\(id.uuidString)"
        case .confirmDelete(let id):  "delete-\(id.uuidString)"
        }
    }
}

// MARK: - A viewmodel (@MainActor @Observable, NebulaViewModel marker)

@MainActor @Observable
final class ItemListViewModel: NebulaViewModel {
    var destination: Destination?

    func edit(_ id: UUID) { destination = .editItem(id) }
    func confirmDelete(_ id: UUID) { destination = .confirmDelete(id) }
    func dismiss() { destination = nil }
}

// MARK: - App

@main
struct MeridianExampleApp: App {
    @State private var router = Router<AppRoute>()

    var body: some Scene {
        WindowGroup {
            MeridianNavigationStack(router: router) {
                RootView()
            } destination: { route in
                switch route {
                case .root:           RootView()
                case .detail(let id): DetailView(id: id)
                case .settings:       SettingsView()
                }
            }
            .onOpenURL { url in
                // Deep link as data: parse → replaceStack. The plain Task
                // inherits the @MainActor isolation of the SwiftUI action, so the
                // concrete router's synchronous replaceStack is called directly
                // (the async port's await would be a no-op here; use the async
                // form when driving the router from a non-MainActor context).
                Task { router.replaceStack(with: DeepLink.parse(url)) }
            }
        }
    }
}

// MARK: - Views (pure functions of state)

private struct RootView: View {
    var body: some View {
        // In a real app: a list of items with NavigationLink(value: AppRoute.detail(id:))
        // pushes onto the typed stack. Kept minimal — the pattern is the point.
        NavigationLink("Settings", value: AppRoute.settings)
            .navigationTitle("Meridian Example")
    }
}

private struct DetailView: View {
    let id: UUID
    var body: some View {
        Text("Detail \(id.uuidString.prefix(8))")
            .navigationTitle("Detail")
    }
}

private struct SettingsView: View {
    var body: some View {
        Text("Settings")
            .navigationTitle("Settings")
    }
}
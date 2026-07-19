# Navigation Patterns

The two patterns `Router` + `MeridianNavigationStack` enable — deep links as data, and type-driven modal destinations — and how they compose.

## Overview

### Deep link as data

A deep link is a pure function `URL -> [Route]`. Parse the URL into a typed `[Route]` stack, then hand it to the router's `replaceStack(with:)`. No simulator needed to test it — assert the array.

```swift
enum AppRoute: NebulaRoute {
    case root
    case detail(id: UUID)
    case settings
}

enum DeepLink {
    static func parse(_ url: URL) -> [AppRoute] {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return [.root]
        }
        var routes: [AppRoute] = [.root]
        for segment in comps.path.split(separator: "/").map(String.init) {
            switch segment {
            case "settings": routes.append(.settings)
            default:
                if let id = UUID(uuidString: segment) { routes.append(.detail(id: id)) }
            }
        }
        return routes
    }
}

// Wire it up — the async port is the cross-actor bridge to the @MainActor router.
.onOpenURL { url in
    Task { router.replaceStack(with: DeepLink.parse(url)) }
}
```

State restoration is the same idea via `Codable`: `Route` is `NebulaRoute` (`Codable`), so `router.path` encodes/decodes directly.

### Type-driven modal destinations — impossible states unrepresentable

Model each feature's modal/sheet/alert destination as a single `Optional<Destination>` enum. Only one destination is active at a time, so "the edit sheet AND the delete alert are showing" is a state the compiler refuses — there is no `editItem && confirmDelete`.

```swift
@MainActor @Observable
final class ItemListViewModel: NebulaViewModel {
    var destination: Destination?

    func edit(_ id: UUID) { destination = .editItem(id) }
    func confirmDelete(_ id: UUID) { destination = .confirmDelete(id) }
    func dismiss() { destination = nil }
}

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

// One binding — the enum decides which sheet; no boolean matrix.
.sheet(item: $vm.destination) { destination in
    switch destination {
    case .editItem(let id):       EditSheet(id: id)
    case .confirmDelete(let id):   ConfirmDeleteSheet(id: id)
    }
}
```

`Identifiable` is hand-rolled (no `@CasePathable` macro — `dependencies: []`). The single optional enum delivers ~90% of the pointfree swift-navigation value natively.

### One stack per tab; push identifier values

One `Router`/`MeridianNavigationStack` per tab — never share a path across tabs (a SwiftUI footgun). Push identifier values (`.detail(id:)`), not full models; destination views load their own data from the identifier.

## Topics

- ``Router``
- ``MeridianNavigationStack``
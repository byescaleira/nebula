# Navigation Patterns

The patterns `Router` + `MeridianNavigationStack` enable — external navigation entries conforming to the router, and type-driven modal destinations — and how they compose.

## Overview

### External navigation entries conforming to the router (Wave N21)

Every external navigation entry — deep links (`myapp://`), universal links (`https://`), Spotlight/Handoff/Siri, Home-screen shortcuts, notification taps, in-app "go here" — is normalized to a `NebulaLink`, resolved by an app-provided `NebulaLinkParser<Route>` port into a `NebulaLinkDestination<Route>` (`.unhandled` / `.present` / `.pushStack` / `.pushStackAndPresent` / `.dismiss`), and applied to the same `NebulaPresentationRouter` the viewmodels use. A `NebulaLinkRouter<Router>` is the one-line glue; the destination→intents translation lives once in the additive `NebulaPresentationRouter.apply(_:)` default extension (dismiss-first for stack-rebuilds to clear any stale modal). This supersedes the ad-hoc `URL → [Route]` function.

```swift
import Nebula
import Meridian

enum AppRoute: NebulaRoute {
    case root
    case detail(id: UUID)
    case settings
    case login             // .fullScreenCover
}

struct AppLinkParser: NebulaLinkParser {
    typealias Route = AppRoute
    func resolve(_ link: NebulaLink) -> NebulaLinkDestination<AppRoute> {
        guard let url = link.url,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return .unhandled }
        var routes: [AppRoute] = [.root]
        for segment in comps.path.split(separator: "/").map(String.init) {
            switch segment {
            case "settings": routes.append(.settings)
            case "login":    return .present(.login)
            default:
                if let id = UUID(uuidString: segment) { routes.append(.detail(id: id)) }
            }
        }
        return routes.count > 1 ? .pushStack(routes) : .unhandled
    }
}

// One router, one parser — every external entry conforms to it.
let linkRouter = NebulaLinkRouter(router: router, parser: AppLinkParser())

// Deep links + universal links via .onOpenURL; Spotlight/Handoff/Siri via .onContinueUserActivity.
ContentView()
    .meridianDeepLinks(linkRouter)
    .meridianUserActivity("com.example.item", linkRouter)
```

`NebulaLink.init(url:)` infers `.universalLink` for `http`/`https`, else `.urlScheme`. The URL is `Sendable`, so `.meridianDeepLinks` captures it cleanly into the `Task`; `.meridianUserActivity` builds the `NebulaLink` **inside** the `.onContinueUserActivity` perform closure (`NSUserActivity` is not `Sendable`) and captures only the Sendable link across the `Task`. No simulator needed to test the parser — assert the `NebulaLinkDestination` value.

Shortcuts (`UIApplicationShortcutItem`) and notification taps (`UNNotificationResponse`) have no SwiftUI View modifier / pull UIKit → build a `NebulaLink` in your delegate and call `linkRouter.open(_:)` (keeps Meridian UIKit-free, valid on all 5 platforms). See the Nebula article <doc:ArchitectureDeepLinks> for the six sources, the SwiftUI-native vs app-constructed split, and the atomicity note.

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
- ``meridianDeepLinks(_:)``
- ``meridianUserActivity(_:_:)``
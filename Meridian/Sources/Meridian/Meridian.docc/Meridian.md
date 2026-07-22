# ``Meridian``

> The presentation-architecture sibling of Nebula — the `@Observable Router` and the modern container trio (`NavigationStack` + `NavigationSplitView` + `TabView`) that render Nebula's Foundation-only navigation model.

Meridian is where SwiftUI lives in the Nebula ecosystem. Nebula ships the navigation **model** (`NebulaRoute` / `NebulaNavigationStack` / `NebulaRouter` / `NebulaPresentationStyle` / `NebulaPresentation` / `NebulaPresentationRouter`) Foundation-only; Meridian ships the `@Observable` concrete `Router` (conforming to `NebulaPresentationRouter`) and the SwiftUI adapters that bind that model to the modern container trio — `MeridianNavigationStack` (`NavigationStack(path:)` + `navigationDestination(for:)` + `.sheet`/`.fullScreenCover`), `MeridianNavigationSplitView`, and `MeridianTabView`.

The split is load-bearing: Meridian is a **separate** local SwiftPM package depending on Nebula (`../`), so `import Meridian` from inside Nebula is an unconditional hard compile error — the Clean Architecture dependency rule (use cases / domain never import presentation) is compiler-enforced across packages, closing the Wave H open risk (SR-1393 only applies within one package). Mirrors pointfreeco/swift-navigation (`SwiftUINavigation` → `SwiftNavigation`).

### Per-route presentation styles + the modern trio (Wave N20)

A route declares **how it is presented** via `NebulaRoute.presentationStyle` — `.push` (the default), `.sheet`, or `.fullScreenCover`; `router.present(route)` dispatches by the declared style, `router.present(route, as:)` overrides at the call site, and `router.dismiss()` clears an active modal or pops one. `MeridianNavigationStack` wires the router's single modal slot to `.sheet(isPresented:)`/`.fullScreenCover(isPresented:)` (the latter gated `#if !os(macOS)` with a `.sheet` fallback on macOS). The trio — `NavigationStack` (push) + `NavigationSplitView` (split) + `TabView` (`Tab(value:)`, one `Router` per tab) — is bound to the router, pickable per screen area; `NavigationView` is deprecated and not used.

### External navigation entries conforming to the router (Wave N21)

Every external navigation entry — deep links, universal links, Spotlight/Handoff/Siri, Home-screen shortcuts, notification taps, in-app "go here" — is funneled through a `NebulaLink` → an app-provided `NebulaLinkParser<Route>` → a `NebulaLinkRouter<Router>` → the same `Router`. Meridian supplies the two SwiftUI-native entry-point adapters: `.meridianDeepLinks(_:)` (wires `.onOpenURL` — covers deep links + universal links) and `.meridianUserActivity(_:_:)` (wires `.onContinueUserActivity` — Spotlight/Handoff/Siri; `NSUserActivity` is not `Sendable`, so the adapter builds the `NebulaLink` inside the perform closure and captures only the `Sendable` link across the `Task`). Shortcuts/notifications are app-constructed `NebulaLink`s (no SwiftUI hook / UIKit → call `linkRouter.open(_:)` from the delegate — Meridian stays UIKit-free, valid on all 5 platforms). Both modifiers are available iOS 14/macOS 11/tvOS 14/watchOS 7 (visionOS via `*`) → no `@available`/`#if os()` gates at Meridian's `.v26` floor. See <doc:NavigationPatterns> and the Nebula article <doc:ArchitectureDeepLinks>.

## Topics

### Router
- ``Router``

### Containers
- ``MeridianNavigationStack``
- ``MeridianNavigationSplitView``
- ``MeridianTabView``

### External navigation (Wave N21)
- ``meridianDeepLinks(_:)``
- ``meridianUserActivity(_:_:)``

### Articles
- <doc:NavigationPatterns>
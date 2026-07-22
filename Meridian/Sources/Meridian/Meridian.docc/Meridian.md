# ``Meridian``

> The presentation-architecture sibling of Nebula — the `@Observable Router` and the modern container trio (`NavigationStack` + `NavigationSplitView` + `TabView`) that render Nebula's Foundation-only navigation model.

Meridian is where SwiftUI lives in the Nebula ecosystem. Nebula ships the navigation **model** (`NebulaRoute` / `NebulaNavigationStack` / `NebulaRouter` / `NebulaPresentationStyle` / `NebulaPresentation` / `NebulaPresentationRouter`) Foundation-only; Meridian ships the `@Observable` concrete `Router` (conforming to `NebulaPresentationRouter`) and the SwiftUI adapters that bind that model to the modern container trio — `MeridianNavigationStack` (`NavigationStack(path:)` + `navigationDestination(for:)` + `.sheet`/`.fullScreenCover`), `MeridianNavigationSplitView`, and `MeridianTabView`.

The split is load-bearing: Meridian is a **separate** local SwiftPM package depending on Nebula (`../`), so `import Meridian` from inside Nebula is an unconditional hard compile error — the Clean Architecture dependency rule (use cases / domain never import presentation) is compiler-enforced across packages, closing the Wave H open risk (SR-1393 only applies within one package). Mirrors pointfreeco/swift-navigation (`SwiftUINavigation` → `SwiftNavigation`).

### Per-route presentation styles + the modern trio (Wave N20)

A route declares **how it is presented** via `NebulaRoute.presentationStyle` — `.push` (the default), `.sheet`, or `.fullScreenCover`; `router.present(route)` dispatches by the declared style, `router.present(route, as:)` overrides at the call site, and `router.dismiss()` clears an active modal or pops one. `MeridianNavigationStack` wires the router's single modal slot to `.sheet(isPresented:)`/`.fullScreenCover(isPresented:)` (the latter gated `#if !os(macOS)` with a `.sheet` fallback on macOS). The trio — `NavigationStack` (push) + `NavigationSplitView` (split) + `TabView` (`Tab(value:)`, one `Router` per tab) — is bound to the router, pickable per screen area; `NavigationView` is deprecated and not used.

## Topics

### Router
- ``Router``

### Containers
- ``MeridianNavigationStack``
- ``MeridianNavigationSplitView``
- ``MeridianTabView``

### Articles
- <doc:NavigationPatterns>
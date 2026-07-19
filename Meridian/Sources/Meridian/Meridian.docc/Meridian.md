# ``Meridian``

> The presentation-architecture sibling of Nebula — the `@Observable Router` and `NavigationStack` wiring that render Nebula's Foundation-only navigation model.

Meridian is where SwiftUI lives in the Nebula ecosystem. Nebula ships the navigation **model** (`NebulaRoute` / `NebulaNavigationStack` / `NebulaRouter`) Foundation-only; Meridian ships the `@Observable` concrete `Router` and the `MeridianNavigationStack` wiring that bind that model to `NavigationStack(path:)` + `navigationDestination(for:)`.

The split is load-bearing: Meridian is a **separate** local SwiftPM package depending on Nebula (`../`), so `import Meridian` from inside Nebula is an unconditional hard compile error — the Clean Architecture dependency rule (use cases / domain never import presentation) is compiler-enforced across packages, closing the Wave H open risk (SR-1393 only applies within one package). Mirrors pointfreeco/swift-navigation (`SwiftUINavigation` → `SwiftNavigation`).

## Topics

### Router
- ``Router``
- ``MeridianNavigationStack``

### Articles
- <doc:NavigationPatterns>
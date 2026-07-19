# Presentation Seams

The Foundation-only navigation model, intent port, and viewmodel marker that let an app (or the sibling Meridian package) implement a data-driven `Router` architecture — without Nebula owning any SwiftUI.

## Overview

Nebula is Foundation-only: it ships no `View`, no `@ViewBuilder`-returning router, no `@Observable`. What it **does** ship is the **navigation model as data** — a typed `[Route]` stack — plus the intent port and a spy test double. The `@Observable` concrete `Router` and the `NavigationStack` wiring live in the sibling **Meridian** package (SwiftUI-bearing); Nebula ships the pure-Swift half they both build on. This is the answer that keeps the dependency pointing **inward** and the Wave H Clean-Architecture dependency rule compiler-enforced across packages.

- ``NebulaRoute`` — the contract for a route: `Hashable & Sendable & Codable`. An app's `Route` enum conforms (`case detail(id: UUID)` — push identifiers, render models).
- ``NebulaNavigationStack`` — a typed `[Route]` stack as a `Sendable`/`Codable`/`Equatable` value type: `push`/`pop`/`popToRoot`/`replaceStack`. Deep links are "build `[Route]`, `replaceStack`" — pure data, testable without a simulator.
- ``NebulaRouter`` — the navigation-intent port (primary associated type `Route`): `push`/`pop`/`popToRoot`/`replaceStack`. The viewmodel holds one via constructor injection; substitute a spy in tests.
- ``NebulaViewModel`` — the bare `Sendable` marker a presentation model conforms to. Nebula ships **only the marker**; the consumer adds `@MainActor @Observable` (Swift 6 friction outside SwiftUI — `@Observable` is a consumer concern).
- ``NebulaSpyRouter`` — a spy router recording every intent as a value (`final class` + `let Mutex`, `Sendable` derived — no `@unchecked`), a drop-in substitute for the port.

### Why a typed `[Route]` over type-erased `NavigationPath`

Compile-time exhaustive handling in `navigationDestination(for: Route.self)`, an inspectable/reorderable stack (matters where `NavigationStack` is reported broken on macOS), and trivial `Codable` restoration. Reach for type-erased `NavigationPath` only when pushing genuinely heterogeneous value types.

### Navigation state lives in the router, not the viewmodel

Keeping the typed stack in the router (the outermost presentation circle) keeps the viewmodel testable and deep-link-replayable: a viewmodel calls `router.push(.detail(id:))` with zero knowledge of destination views, and deep-link handling is "parse → `router.replaceStack(with:)`".

## Topics

### Routes & model
- ``NebulaRoute``
- ``NebulaNavigationStack``
- ``NebulaNavigationStack/push(_:into:)``
- ``NebulaNavigationStack/pop(_:into:)``
- ``NebulaNavigationStack/popToRoot(_:)``
- ``NebulaNavigationStack/replaceStack(_:into:)``

### Ports & markers
- ``NebulaRouter``
- ``NebulaViewModel``

### Test doubles
- ``NebulaSpyRouter``
- ``NebulaSpyRouter/Intent``
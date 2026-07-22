# Presentation Seams

The Foundation-only navigation model, intent port, and viewmodel marker that let an app (or the sibling Meridian package) implement a data-driven `Router` architecture — without Nebula owning any SwiftUI.

## Overview

Nebula is Foundation-only: it ships no `View`, no `@ViewBuilder`-returning router, no `@Observable`. What it **does** ship is the **navigation model as data** — a typed `[Route]` stack — plus the intent port and a spy test double. The `@Observable` concrete `Router` and the `NavigationStack` wiring live in the sibling **Meridian** package (SwiftUI-bearing); Nebula ships the pure-Swift half they both build on. This is the answer that keeps the dependency pointing **inward** and the Wave H Clean-Architecture dependency rule compiler-enforced across packages.

- ``NebulaRoute`` — the contract for a route: `Hashable & Sendable & Codable`, plus an additive ``NebulaRoute/presentationStyle`` (default `.push`) that declares **how** the route is presented. An app's `Route` enum conforms (`case detail(id: UUID)` — push identifiers, render models).
- ``NebulaNavigationStack`` — a typed `[Route]` stack as a `Sendable`/`Codable`/`Equatable` value type: `push`/`pop`/`popToRoot`/`replaceStack`. Deep links are "build `[Route]`, `replaceStack`" — pure data, testable without a simulator.
- ``NebulaRouter`` — the navigation-intent port (primary associated type `Route`): `push`/`pop`/`popToRoot`/`replaceStack`. The viewmodel holds one via constructor injection; substitute a spy in tests.
- ``NebulaPresentationStyle`` — `.push`/`.sheet`/`.fullScreenCover` (Wave N20): how a route is presented. Declared on the route via ``NebulaRoute/presentationStyle``.
- ``NebulaPresentation`` — the navigation-as-data model owning the typed `[Route]` push path **and** a single modal slot (`present`/`present(_:as:)`/`dismiss`); push-path ops delegate to ``NebulaNavigationStack``, present/dismiss live in `static` `inout` helpers — single source of truth (Wave N20).
- ``NebulaPresentationRouter`` — a sub-protocol of ``NebulaRouter`` adding async `present(_:)`/`present(_:as:)`/`dismiss()`; existing `NebulaRouter` conformers are untouched (Wave N20).
- ``NebulaViewModel`` — the bare `Sendable` marker a presentation model conforms to. Nebula ships **only the marker**; the consumer adds `@MainActor @Observable` (Swift 6 friction outside SwiftUI — `@Observable` is a consumer concern).
- ``NebulaSpyRouter`` — a spy router recording every intent as a value (`final class` + `let Mutex`, `Sendable` derived — no `@unchecked`), a drop-in substitute for the port — conforms to ``NebulaPresentationRouter``.

### Per-route presentation styles (Wave N20)

A route declares **how it is presented** via ``NebulaRoute/presentationStyle`` — `.push` (the default), `.sheet`, or `.fullScreenCover`. `present(_:)` dispatches by the declared style (a `.push` route pushes onto the path; a modal route fills the single modal slot); `present(_:as:)` overrides at the call site. `dismiss()` clears an active modal, else pops one — never both. The single modal slot matches SwiftUI (one sheet/cover at a time). The Meridian adapter wires the slot to `.sheet(isPresented:)`/`.fullScreenCover(isPresented:)` (not `.sheet(item:)` — `Route` need not be `Identifiable`); `fullScreenCover` is gated `#if !os(macOS)` with a `.sheet` fallback on macOS.

### The modern container trio (Wave N20)

`NavigationStack` (push) + `NavigationSplitView` (split — subsumes the deprecated `NavigationView`) + `TabView` (`Tab(value:)`, one `Router` per tab) are bound to the router, pickable per screen area — all in the Meridian sibling. `NavigationView` is deprecated and not used.

### Why a typed `[Route]` over type-erased `NavigationPath`

Compile-time exhaustive handling in `navigationDestination(for: Route.self)`, an inspectable/reorderable stack (matters where `NavigationStack` is reported broken on macOS), and trivial `Codable` restoration. Reach for type-erased `NavigationPath` only when pushing genuinely heterogeneous value types.

### Navigation state lives in the router, not the viewmodel

Keeping the typed stack in the router (the outermost presentation circle) keeps the viewmodel testable and deep-link-replayable: a viewmodel calls `router.push(.detail(id:))` with zero knowledge of destination views, and deep-link handling is "parse → `router.replaceStack(with:)`".

### External navigation entries (Wave N21)

Every external navigation entry — deep links, universal links, Spotlight/Handoff/Siri, Home-screen shortcuts, notification taps, in-app "go here" — conforms to the same ``NebulaPresentationRouter``: a ``NebulaLink`` (a `Sendable` normalization of the event) is resolved by an app-provided ``NebulaLinkParser`` port into a ``NebulaLinkDestination`` (`.unhandled`/`.present`/`.pushStack`/`.pushStackAndPresent`/`.dismiss`), then `apply`-ed to the router via an additive ``NebulaPresentationRouter/apply(_:)`` **default extension method** (dismiss-first for stack-rebuilds to clear any stale modal). A ``NebulaLinkRouter`` is the one-line glue (`open(_:)` → `await router.apply(parser.resolve(link))`); a ``NebulaCompositeLinkParser`` registers several parsers (first-non-`.unhandled`-wins). See <doc:ArchitectureDeepLinks> for the six sources, the SwiftUI-native vs app-constructed split, and the atomicity note.

## Topics

### Routes & model
- ``NebulaRoute``
- ``NebulaRoute/presentationStyle``
- ``NebulaNavigationStack``
- ``NebulaNavigationStack/push(_:into:)``
- ``NebulaNavigationStack/pop(_:into:)``
- ``NebulaNavigationStack/popToRoot(_:)``
- ``NebulaNavigationStack/replaceStack(_:into:)``
- ``NebulaPresentationStyle``
- ``NebulaPresentation``
- ``NebulaPresentation/present(_:as:into:modal:style:)``
- ``NebulaPresentation/dismiss(path:modal:style:)``

### Ports & markers
- ``NebulaRouter``
- ``NebulaPresentationRouter``
- ``NebulaPresentationRouter/present(_:as:)``
- ``NebulaPresentationRouter/dismiss()``
- ``NebulaViewModel``

### Test doubles
- ``NebulaSpyRouter``
- ``NebulaSpyRouter/Intent``

### External navigation entries (Wave N21)
- ``NebulaLink``
- ``NebulaLink/Source``
- ``NebulaLinkDestination``
- ``NebulaLinkParser``
- ``NebulaCompositeLinkParser``
- ``NebulaLinkRouter``
- ``NebulaPresentationRouter/apply(_:)``
- ``NebulaStubLinkParser``
- ``NebulaSpyLinkParser``
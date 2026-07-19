---
tags: [padroes, architecture, presentation, navigation, router, nebula]
aliases: [Nebula presentation seams, NebulaNavigationStack, NebulaRouter, NebulaRoute, NebulaSpyRouter]
related: [[nebula-presentation-architecture]], [[nebula-presentation-target-split]], [[presentation-architecture-risks]], [[presentation-architecture-open-questions]], [[nebula-test-doubles]], [[nebula-usecase]], [[nebula-registry-di]]
status: shipped
shipped: "2026-07-19 (Wave I)"
---

# Nebula Presentation Seams (Wave I — shipped)

The Foundation-only presentation half of the [[nebula-presentation-architecture]] recommendation. Wave I ships the **navigation model as data** + the intent port + a spy test double + the viewmodel marker — the pure-Swift surface the sibling **Meridian** package (Wave II) builds its `@Observable Router` on. Source of truth = `Sources/Nebula/Architecture/Presentation/`; this note is synthesis. On conflict, root doc/code wins.

## What shipped (5 symbols, all Foundation-only)

| Symbol | Shape | Role |
|---|---|---|
| `NebulaRoute` | `protocol: Hashable, Sendable, Codable` | The route contract — an app's `Route` enum conforms. Push **identifier values** (`case detail(id: UUID)`), not full models. |
| `NebulaNavigationStack<Route>` | `struct: Sendable, Codable, Equatable` | The **navigation model**: a typed `[Route]` stack, `push`/`pop`/`popToRoot`/`replaceStack`. Deep links = "build `[Route]`, `replaceStack`" — pure data, testable without a simulator. |
| `NebulaRouter<Route>` | `protocol<Route>: Sendable` (primary assoc type, SE-0346) | The navigation-intent **port**. Non-mutating methods (conformers are reference types). The viewmodel holds one via constructor injection. |
| `NebulaViewModel` | `protocol: Sendable` (marker) | The viewmodel contract. Nebula ships **only the marker**; the consumer adds `@MainActor @Observable`. |
| `NebulaSpyRouter<Route>` | `final class` + `let Mutex<[Intent]>`, `Sendable` **derived** | Spy router recording every intent as a value (`Intent` enum `Sendable`/`Equatable`). Drop-in for the port in tests. Mirrors [[nebula-test-doubles]] `NebulaSpyUseCase`. |

## Design decisions (binding-rule compliant)

- **Single source of truth for stack mutation**: `NebulaNavigationStack` holds the logic in `static func …(into: inout [Route])` helpers. The `mutating` instance methods delegate to them; the Meridian `@Observable Router` (Wave II) will also delegate — no duplication between the pure model and the observable wrapper.
- **Typed `[Route]` over type-erased `NavigationPath`**: compile-time exhaustive `navigationDestination(for: Route.self)` handling, inspectable/reorderable stack (defensive vs `NavigationStack`'s reported macOS bugs — [[presentation-architecture-risks]] #4), trivial `Codable` restoration. (risk #4 evidence *for* the Foundation-only model.)
- **`NebulaRouter` requirements are `async`** (the Swift 6 fix for an on-actor conformer of a nonisolated, Foundation-only port). A synchronous `@MainActor` method witnesses a nonisolated `async` requirement — the `await` performs the actor hop — so the Meridian `@MainActor @Observable Router` conforms WITHOUT Nebula taking a `@MainActor` dependency (binding rule: app supplies isolation). The async port is also the **cross-actor bridge**: an off-actor deep-link parser can `await router.replaceStack(with:)` to drive the on-actor router. Conformers keep **sync** impls (a sync method witnesses an async requirement; no hop for a nonisolated sync impl, an actor hop for an isolated one) — concrete calls stay sync, only `any NebulaRouter` calls `await`. `pop()` and `pop(_:)` are two explicit requirements (default args are NOT permitted in a protocol method, verified — so the no-arg form is its own requirement, not a default).
- **No `@Observable` in Nebula** ([[presentation-architecture-risks]] #3 / Q7): Observation-module (not SwiftUI) but Swift 6 friction outside SwiftUI. The consumer (Meridian/app) adds `@MainActor @Observable`; a `@MainActor @Observable final class` is `Sendable` by isolation, so conforming to `NebulaViewModel` is free.
- **`Sendable` derived everywhere — no `@unchecked`**: `NebulaNavigationStack` derives Sendable (`Route: Sendable` → `[Route]: Sendable`); `NebulaSpyRouter` is a `final class` with all-`let` `Sendable` properties (the `let Mutex`) → synthesized Sendable, mirroring `NebulaSpyUseCase` / `NebulaError.Box` (NOT the `NebulaMemoryLogHandler` `@unchecked` exception).
- **No SwiftUI, no UIKit, no `#if canImport(UIKit)`**: the seams are pure `import Foundation` (+ `import Synchronization` for the spy's `Mutex`). 5-platform at `.v26`, no above-floor gates.
- **`NebulaRouter` is a port, not a "router that routes"** ([[presentation-architecture-risks]] #6): the *hollow critique collapses* because the Foundation core holds a **typed path/stack model** (`NebulaNavigationStack`), not a bare `@Sendable (Route) -> Void` closure. Deep-link parsing, back-stack reduction, route logging, `Codable` restoration are all testable in pure Swift — the SwiftUI adapter (Meridian) just renders the model.

## TDD fit (why this shape)

- Navigation-as-data: `#expect(stack.path == [.root, .detail(id:)])`, `#expect(spy.intents() == [.push(...), .pop(1)])` — pure value assertions, no simulator.
- `NebulaSpyRouter` substitutes for `any NebulaRouter<R>` in a viewmodel's constructor — the only architecture where the test double plugs in with zero adaptation (contrast TCA's `DependencyKey` wrappers — [[presentation-architecture-risks]] #1).
- Deep-link round-trip = `Codable` encode/decode + `replaceStack` assertion — testable without rendering.
- Red-green maps onto the port → model → adapter ordering: define `NebulaRouter`/`NebulaRoute`, write the viewmodel against `NebulaSpyRouter` (red), implement (green), then the Meridian `@Observable Router` + `View` around it.

## What is NOT in Wave I (deferred)

- The `@Observable Router`, `NavigationStack` wiring, `navigationDestination(for:)` factory → **Meridian** (Wave II).
- Type-driven `Optional<Destination>` enum destinations, deep-link parser pattern, example app → Wave III.
- ADR + versioning (Meridian N ↔ Nebula N) + per-platform `xcodebuild` gate → Wave IV.

## Open decisions (still the owner's)

- [[presentation-architecture-open-questions]] Q4 resolved → **(d) Meridian sibling package** (subdir `Meridian/` in this repo, path-dep on Nebula). Q5 naming ("Meridian"), Q6 version coordination land in Wave IV.

## Build gate (Wave I)

`rm -rf .build && swift build && swift test && swift build -c release` → 525 tests / 110 suites green, zero concurrency warnings, release clean. +16 tests over 0.2.0 (509). New files have no `#if os()` (Foundation + Synchronization only); full per-platform `xcodebuild` gate in Wave IV.
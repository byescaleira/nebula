---
tags: [padroes, architecture, presentation, swiftui, mvvm, coordinator, tdd, nebula]
aliases: [Nebula presentation architecture, NebulaUI architecture, presentation layer,MVVM Nebula, Coordinator Nebula]
related: [[nebula-clean-architecture-toolkit]], [[nebula-presentation-target-split]], [[nebula-usecase]], [[nebula-repository]], [[nebula-registry-di]], [[nebula-swift6-concurrency]], [[presentation-architecture-risks]], [[presentation-architecture-open-questions]], [[nebula-test-doubles]]
status: researched
researched: "2026-07-19"
---

# Nebula Presentation Architecture (2026 research)

The **third surface** question: which presentation architecture (state pattern + navigation/routing) should the Nebula/Cosmos ecosystem recommend — and ship seams for — given the binding rules (`dependencies: []`, no third-party; Nebula Foundation-only / no SwiftUI; Swift 6.3 / OS 26 / `@Observable` era)? Source of truth = root docs + shipped `Sources/Nebula/Architecture/`; this note is synthesis. On conflict, root doc/code wins. Canonical hub for the presentation half; the **target/module split** is [[nebula-presentation-target-split]]; risks in [[presentation-architecture-risks]]; open questions in [[presentation-architecture-open-questions]].

## The binding constraints (load-bearing)

- **No third-party deps** (`dependencies: []`) — TCA, swift-navigation, FlowStacks, BlocSwift, SUICoordinator are **out as imports**, in as **pattern inspiration only**. We re-implement the essence natively (pure Swift + Foundation + SwiftUI).
- **Nebula is Foundation-only** (no `import SwiftUI`/`UIKit`/`#if canImport(UIKit)`) — Nebula cannot ship a `View`, a `@ViewBuilder`-returning router, or anything that binds `NavigationStack`. It can ship **Foundation-only presentation seams** (ports + `Route` value types + markers) — see [[nebula-presentation-target-split]] option (a).
- **Cosmos is a design system** (Atoms/Molecules/Organisms/Modifiers/Screen + tokens), already imports SwiftUI, but has **no** router/coordinator/navigation surface. Conflating architecture into Cosmos muddies its identity (option (c), rejected).
- **Swift 6.3 / OS 26 / `@Observable` era** — `@Observable` macro (iOS 17+, the 2026 default), `NavigationStack` + `navigationDestination(for:)`, Swift 6 strict concurrency.

## The 2026 landscape (shortlist, dependency-free reframing)

Full survey in [[presentation-architecture-risks]] / agent findings. Ranked for a **new Swift 6 / OS 26 / SwiftUI codebase under `dependencies: []`**:

1. **MV with `@Observable` + a native `Router` per tab** — Apple's de-facto default (WWDC25 S266, WWDC26 S269 `@State`-as-macro). `@MainActor @Observable final class` models + `NavigationStack(path:)` + `Hashable`/`Codable` `Route` enum + `navigationDestination(for: Route.self)`. Zero deps, zero framework friction, OS-26 features land here first. **Baseline.**
2. **MVVM `@Observable` viewmodel + native typed-`[Route]` Router** — one `@MainActor @Observable final class` viewmodel per screen (owned via `@State`, shared via `.environment(model)`, bindings via `@Bindable`) + a **typed-`[Route]` `@Observable Router` per tab/flow** (NOT a Coordinator tree). The 2026 community consensus for anything beyond toy screens. **Recommended** — see TDD fit below.
3. **Type-driven enum destinations** (swift-navigation's *pattern*, not the lib) — model each feature's modal/sheet/alert destination as a single `Optional<Destination>` enum so only one destination is active (compiler-enforced "impossible states unrepresentable"). The **scalability layer** adopted natively — no `@CasePathable` macro dep; `Hashable`/`Identifiable` route values + `sheet(item:)` + a `switch` deliver ~90% of the value (the single optional enum is pure Swift).
4. **VIPER / VIP (Clean Swift)** — structurally isomorphic to Nebula's port/use-case/adapter (Interactor=use case, Worker=repository, Presenter=output port, Router=navigator) and TDD is its *intended* workflow. **But**: SwiftUI adaptations are grafted-on (UIKit-era retain-cycle/wireframe machinery), per-scene boilerplate is heavy, 2024-2026 framework-native guidance is thin. Strong structural match, weak SwiftUI ergonomics — a reference pattern, not the shipping default.
5. **TCA / MVI / BLoC** — TCA is the most powerful (`TestStore`, exhaustive effect ordering) **but** structurally rejects Nebula's constructor-injection DI (requires `@Dependency`/`DependencyKey` wrappers — global-default + scoped-override), has documented Swift 6 macro-isolation traps, and broke on Xcode 26.4. MVI/BLoC are patterns without ecosystem. **Out** (dep + DI clash + Swift 6 friction).

## Recommendation: MVVM `@Observable` + native typed-`[Route]` Router (zero deps, NO Coordinator tree)

**Pattern**: `@MainActor @Observable final class` viewmodels (one per screen) + a **typed-`[Route]` `@Observable Router` per tab/flow** (NOT a Coordinator tree) + `NavigationStack(path: $router.path)` + `Hashable`/`Sendable`/`Codable` `Route` enum + `navigationDestination(for: Route.self)` + per-feature **type-driven enum destinations** (`Optional<Destination>` enum driving `sheet(item:)`/`alert(item:)`). Viewmodels take Nebula ports/use-cases via **constructor injection**; navigation state lives in the Router (NOT the screen viewmodel — keeps viewmodels testable and deep-link-replayable). **100% native, zero deps.**

### Router vs Coordinator — owner preference: Router (data-driven, no object tree)

In 2026 literature "Router" and "Coordinator" are sometimes conflated, but the distinction the owner is drawing is the real one:
- **Coordinator** = a *tree of coordinator objects* (AppCoordinator → AuthCoordinator → MainCoordinator, each owning a flow) — the Khanlou/UIKit lineage. Ceremony + object-graph overhead. **Rejected for this ecosystem** (owner preference).
- **Router** = a *data-driven navigation-state owner* per scope (tab/flow): an `@Observable` class holding a **typed `[Route]` array** (not type-erased `NavigationPath`) with `push`/`pop`/`popToRoot`/`replaceStack`, injected via `.environment(router)`. Views call `router.push(.detail(id))` with zero knowledge of destination views. Light, testable, no object tree.

The **most recent + scalable Router pattern in 2026** is the combination: (1) typed-`[Route]` stack Router per tab + (2) `navigationDestination(for: Route.self)` view factory + (3) per-feature type-driven enum destinations. This is exactly what Apple's **Backyard Birds** sample does (`enum AppScreen: Codable, Hashable, Identifiable` + `NavigationStack(path:)` + `.navigationDestination(for:)` — **no Coordinator type at all**) and the 2026 community consensus calls "Router." Scalability comes from **enum composition** (each feature owns its `Route`/`Destination` enum), **deep-links-as-data** (`replaceStack(with: parsedRoutes)` — pure, testable), **`Codable` routes** → state restoration, and one Router per tab (never share a path across tabs). No coordinator ceremony.

**Typed `[Route]` over type-erased `NavigationPath`**: compile-time exhaustive handling, inspectable/reorderable stack (matters because `NavigationStack` is reported broken on macOS — Dave DeLong Jan 2026; the UI-free typed stack is defensive), trivial `Codable` restoration. Reach for type-erased `NavigationPath` only when pushing genuinely heterogeneous value types.

**Type-driven enum destinations (the scalability layer, native)**: model each feature's modal/sheet/alert destination as a single `Optional<Destination>` enum so only one destination is active — "impossible states unrepresentable," compiler-enforced. This is swift-navigation's *pattern*; under `dependencies: []` we re-implement it natively (no `@CasePathable` macro dep) — `Hashable`/`Identifiable` route values + a `switch` + `sheet(item:)` already deliver ~90% of the value (the single optional enum itself is pure Swift). For deep drill-down `NavigationStack` flows, the typed `[Route]` stack handles recursion; the enum-destination layer handles modals.

### Why this wins on the three axes the owner named

**TDD fit (Swift Testing + Nebula toolkit)** — Tier 1 in the TDD research:
- Viewmodel intent methods are plain `async throws` functions → `#expect(vm.state == …)` one-liners; `#expect(throws: NebulaError.X)` for typed failures; `confirmation { … }` for `NebulaErrorConfiguration` handler fires.
- `NebulaFakeRepository` / `NebulaStubUseCase` / `NebulaSpyUseCase` plug in via constructor injection with **zero adaptation** — the only architecture where this is true (TCA requires `DependencyKey` wrappers; that's why TCA is out).
- Navigation-as-data: `#expect(router.path == [.main, .detail(id)])` — deep links, back/forward, flow assertions are pure unit tests, no simulator.
- Red-green-refactor maps 1:1 onto Nebula's port → use case → adapter ordering (define `NebulaInputPort`/`NebulaOutputPort`, write `NebulaUseCase` against `NebulaFakeRepository` (red), implement (green), then build the viewmodel/Router/View around it).
- **Pitfall to avoid**: `@MainActor` isolation propagates into tests and disables parallel execution — keep only the thin UI-facing layer `@MainActor`; push heavy logic into non-isolated `NebulaUseCase` bodies (which run off-actor and return `Sendable` results). Snapshot tests are **regression tools, not TDD tools** — push logic into testable layers, keep `View`s pure functions of state.

**Nebula infrastructure fit**:
- Viewmodel = the driving adapter that calls `NebulaUseCase<I, O>.execute(_:)` / `executeTyped(_:)`; composes `NebulaRepository` ports; surfaces `NebulaError`/layer errors; routes via a `NebulaNavigator`-shaped port.
- Router = navigation state owner; a `Route` enum is a `NebulaDTO`-shaped value type crossing the presentation boundary; deep-link parsing is a pure function over `Route`.
- DI = explicit-parameter constructor injection (the `NebulaRegistry` primary path, [[nebula-registry-di]]) — viewmodels receive their ports through `init`, never via `@Environment` globals (test-hostile).

**SwiftUI + states fit (2026)** — see [[presentation-architecture-risks]] for the full primitive map:
- `@Observable` (Observation module, SE-0395 — **not** SwiftUI, doesn't pull Combine) is the state owner; `@State` = ownership, `.environment(model)` + `@Environment(Model.self)` = shared, `@Bindable` = bindings only, plain `let` = dependency only. WWDC26 upgrades `@State` to a macro (lazy init, back-ported to iOS 17).
- Viewmodel is `@MainActor @Observable final class` → `Sendable` by isolation; `.task { await vm.load(useCase:) }` inherits `@MainActor` + auto-cancels; the `NebulaUseCase` runs off-actor, returns a `Sendable` result (`NebulaError` is `Sendable`).
- `NavigationStack(path: $router.path)` + `navigationDestination(for: Route.self)` type-driven routing; **typed `[Route]` array preferred** over type-erased `NavigationPath` (compile-time exhaustive, trivial `Codable` restoration); push **identifier values** (`.detail(id)`) not full models; one `NavigationStack` per tab (never share a path across tabs).
- SE-0466 default-MainActor isolation (Swift 6.2) is an **app-level** setting — Nebula stays `nonisolated` default (the explicitly-recommended carve-out for non-UI frameworks). SE-0475 `Observations` AsyncSequence (iOS 26, stdlib Observation module) is a non-Combine, non-SwiftUI observation path for consumer recipes — not a Nebula dependency.

### Where the pieces live (the target decision — summary)

- **Foundation-only seams** (`NebulaRouter`/`NebulaNavigator` ports, `Route` value-type guidance, `NebulaViewModel`/`NebulaPresenter` markers) → **Nebula** (option a). Meaningful, not hollow — the `swift-navigation` `SwiftNavigation` core precedent ships `UINavigationPath`/`UIBinding`/`AlertState` value types Foundation-only; Nebula's seams let route-resolution/deep-link-parsing/back-stack-reduction be tested in pure Swift. `@Observable` itself is Observation-module (not SwiftUI) but **Nebula should NOT ship `@Observable`** — documented Swift 6 friction outside SwiftUI (Donny Wals, Jared Sinclair); it's a consumer concern. A `NebulaViewModel` **marker protocol** is the right shape.
- **SwiftUI-bound router/viewmodel-base** → either a **new sibling package** (option d, recommended — the only split that compiler-enforces the Clean Architecture dependency rule across packages, closing the Wave H open risk) or **the app** (option e, the holding-pattern fallback, Apple Backyard Birds posture).
- Full option-by-option analysis + compile-time-enforcement regimes in [[nebula-presentation-target-split]].

## Decision status

**Researched, not yet decided.** The architecture pattern (MVVM `@Observable` + native typed-`[Route]` Router, zero deps, **no Coordinator tree** — owner preference) is a strong, binding-rule-compliant recommendation. The **target split** (option d new sibling package vs. option a+e holding pattern) is the open decision the owner must make — framed in [[presentation-architecture-open-questions]]. Implementation waves will follow the approved plan pattern (H1→H4 with build gates) once the target decision lands.
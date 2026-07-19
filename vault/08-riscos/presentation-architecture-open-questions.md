---
tags: [riscos, architecture, presentation, decisions, nebula]
aliases: [presentation architecture open questions, NebulaUI decisions, Meridian decisions]
related: [[nebula-presentation-architecture]], [[nebula-presentation-target-split]], [[presentation-architecture-risks]], [[nebula-clean-architecture-toolkit]], [[nebula-registry-di]]
status: decided
researched: "2026-07-19"
decided: "2026-07-19 (Waves I–III shipped)"
---

# Presentation Architecture — Open Questions (owner decisions)

The research ([[nebula-presentation-architecture]], [[nebula-presentation-target-split]], [[presentation-architecture-risks]]) converges on a strong recommendation but leaves **owner-level decisions** before implementation. Each has alternatives + a recommendation. These map to the owner's two questions: *"qual arquitetura"* (Q1–Q3) and *"vale ficar nesse mesmo target desse mesmo projeto"* (Q4–Q6).

## Q1. State/navigation pattern — which architecture?

**Recommendation: MVVM `@Observable` + native typed-`[Route]` Router (zero deps, NO Coordinator tree).**
- `@MainActor @Observable final class` viewmodels (one per screen) + a **typed-`[Route]` `@Observable Router` per tab/flow** + `NavigationStack(path: $router.path)` + `Hashable`/`Sendable`/`Codable` `Route` enum + `navigationDestination(for: Route.self)` + per-feature type-driven enum destinations.
- Viewmodels take Nebula ports/use-cases via **constructor injection**; nav state in the Router (not the viewmodel — keeps viewmodels testable + deep-link-replayable).
- **Alternatives rejected**: TCA (dep + DI clash + Swift 6 friction); VIPER/VIP (structural match but SwiftUI-grafted + heavy boilerplate — kept as reference); MVI/BLoC (no ecosystem); swift-navigation/FlowStacks (deps); **Coordinator tree** (owner preference — see Q2). The **type-driven-enum-destination** pattern (swift-navigation's idea) is adopted as the **scalability layer** — hand-rolled, no `@CasePathable` macro dep.

## Q2. Navigation shape — Router (data-driven) vs Coordinator (object tree)?  ← owner decision: Router

**Recommendation: typed-`[Route]` Router per tab/flow. NO Coordinator tree.** (Owner preference: dislikes Coordinator; wants the most-recent scalable Router pattern.)
- **Router** = data-driven navigation-state owner per scope: `@Observable` class holding a **typed `[Route]` array** (NOT type-erased `NavigationPath`) with `push`/`pop`/`popToRoot`/`replaceStack`, injected via `.environment(router)`. One Router per tab (never share a path across tabs). Deep links = "parse URL → build `[Route]` → `replaceStack`" — pure data, fully testable without a simulator.
- **Coordinator (rejected)** = a *tree of coordinator objects* (AppCoordinator → AuthCoordinator → MainCoordinator, each owning a flow) — the Khanlou/UIKit lineage. Ceremony + object-graph overhead; `@ViewBuilder`-returning coordinators are test-hostile (`_ConditionalContent`); `@Environment`-injected coordinators are global state. Out by owner preference.
- **Most-recent + scalable (2026)**: the typed-`[Route]` stack Router + `navigationDestination(for: Route.self)` view factory + per-feature `Optional<Destination>` enum destinations. This is what Apple's **Backyard Birds** does (`enum AppScreen` + `NavigationStack(path:)`, **no Coordinator type**) and the 2026 consensus calls "Router." Scales via **enum composition** (each feature owns its `Route`/`Destination`), **`Codable` routes** → state restoration, deep-links-as-data. Prefer typed `[Route]` over `NavigationPath` (compile-time exhaustive + inspectable — defensive vs `NavigationStack`'s macOS bugs, risk #4).
- If a genuinely nested/reused multi-step flow appears, model it as a **typed `[Route]` sub-stack owned by a feature Router** — NOT a coordinator object. The Router pattern covers the coordinator use cases without the object tree.

## Q3. Does Nebula ship Foundation-only presentation seams, or stay a pure architecture-toolkit (UseCase/Repository/Registry only)?

**Recommendation: ship the Foundation-only seams** (`NebulaRouter`/`NebulaNavigator` ports, `Route` value-type guidance, `NebulaViewModel`/`NebulaPresenter` **marker protocols** — NOT `@Observable`).
- Meaningful, not hollow, IF the core holds a typed path/stack (deep-link parsing, back-stack reduction, route logging testable in pure Swift) — `swift-navigation` `SwiftNavigation` core precedent.
- `@Observable` stays in the consumer (app / Meridian) — Observation-module but Swift 6 friction outside SwiftUI (Donny Wals/Jared Sinclair); Nebula ships a marker, the app adds `@Observable`.
- **Alternative**: ship nothing presentation-related in Nebula (pure toolkit of UseCase/Repository/Registry seams) and let the app own everything. Honest but leaves the architecture story incomplete for a library that IS an architecture library. The seams are the natural precursor to option (d)'s Foundation core anyway.

## Q4. Target/module split — new sibling package (d) vs holding pattern (a)+(e)?  ← the big one

**Recommendation: option (d), a new sibling package ("Meridian" working name) — IF the ecosystem is meant to be a complete architecture toolkit.**
- Only option that **compiler-enforces** the Clean Architecture dependency rule across packages (closes the Wave H open risk — `import Meridian` from Nebula is a hard error; SR-1393 doesn't cross package boundaries). Mirrors `swift-navigation` (`SwiftUINavigation` → `SwiftNavigation`). Nebula + Cosmos stay `dependencies: []` + pure. Cleanest TDD (Foundation value types in Nebula, SwiftUI routers in Meridian).
- **Fallback — option (a)+(e)**: if the third-package maintenance budget isn't available now, ship Foundation-only seams in Nebula (Q3) + document the SwiftUI binding pattern for the app to own. Holding pattern; natural precursor to (d).
- **Rejected**: (b) `NebulaUI` target inside Nebula package (violates "Foundation-only" at target level — TCA compromise + SR-1393 leakage); (c) in Cosmos (conflates design-system identity, breaks Cosmos `dependencies: []` or disconnects from Nebula seams).
- **The real trade-off**: NOT the binding-rule tension (d honors it) — it's **maintenance budget for a third package vs. completeness of the architecture story**. Complete toolkit → (d). Toolkit-of-seams + app owns the driving adapter → (a)+(e) (Backyard Birds precedent).

## Q5. Package naming (if Q4 = d)

**Recommendation: "Meridian"** (working name) — evokes navigation/orientation, distinct from Nebula/Cosmos, no namespace clash. Alternatives: `NebulaFlow`, `CosmosFlow`, `NebulaUI`, `NebulaNavigation`. `NebulaUI` is misleading (Nebula is Foundation-only; this would muddy the brand). Decide alongside Q4.

## Q6. Version coordination (if Q4 = d)

**Recommendation: Meridian N ↔ Nebula N ↔ OS N** (mirror the Nebula N ↔ OS N versioning policy). Meridian depends on Nebula at the same major. A Nebula major bump lets a Meridian major bump. Within a major: semver minor/patch. Policy in `VERSIONING.md` extended; changes in `CHANGELOG.md`. Decide alongside Q4.

## Q7. `@Observable` location (cross-cutting)

**Recommendation: NOT in Nebula.** `@Observable` is Observation-module (not SwiftUI) but has Swift 6 friction outside SwiftUI; Nebula ships a `NebulaViewModel` marker protocol, the consumer (app / Meridian) adds `@Observable`. This honors Nebula's "no SwiftUI, app supplies its own isolation/`@Observable`" stance. SE-0466 default-MainActor isolation stays app-level (Nebula keeps `nonisolated` default).

## Q8. Test-support target?

**Recommendation: defer.** `swift-dependencies` splits a `DependenciesTestSupport` product to isolate test-only APIs. A future `NebulaTestSupport` (or Meridian equivalent) could isolate test doubles / `withDependencies`-style helpers — but the shipped in-target test doubles (`NebulaFakeRepository`/`Stub`/`Spy`, decision #8) already cover this. Revisit if a test-only API leaks into the shipping surface.

## Decision status

**DECIDED (2026-07-19) and shipped as Waves I–III.** All recommendations adopted:

- **Q1/Q2/Q3** → MVVM `@Observable` + native typed-`[Route]` Router (NO Coordinator tree — owner preference); Foundation-only seams shipped in Nebula (`Sources/Nebula/Architecture/Presentation/`). See [[nebula-presentation-seams]].
- **Q4** → **option (d), new sibling package "Meridian"** (`Meridian/`, subdir package, `.package(path: "../")`). `import Meridian` from Nebula is a hard compile error → Clean Architecture rule compiler-enforced across packages; closes the Wave H open risk (SR-1393 only applies within one package's `.build`). See [[nebula-meridian-router]].
- **Q5** → "Meridian" (kept the working name). **Q6** → Meridian N ↔ Nebula N ↔ OS N lockstep; policy added to `VERSIONING.md`.
- **Q7** → `@Observable` in Meridian, NOT Nebula (`NebulaViewModel` is a bare `Sendable` marker). **Q8** → deferred (in-target test doubles sufficient).

The ADR is in `DECISIONS.md` (2026-07-19 "Presentation architecture" row, Status: Accepted). The one Swift 6 wrinkle that surfaced during implementation — the `NebulaRouter` port had to be **async** so the `@MainActor @Observable` Meridian `Router` can conform while Nebula stays `@MainActor`-free — is recorded in the ADR + [[nebula-meridian-router]]. Build gates: 525 Nebula tests / 13 Meridian tests, zero concurrency warnings. See [[nebula-presentation-destinations-deeplink]] for the deep-link + type-driven-destination patterns (Wave III).
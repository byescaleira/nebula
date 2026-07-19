---
tags: [padroes, architecture, spm, modularization, presentation, nebula]
aliases: [Nebula target split, NebulaUI, Meridian, NebulaFlow, presentation module split, compile-time dependency rule]
related: [[nebula-presentation-architecture]], [[nebula-spm-architecture]], [[nebula-clean-architecture-toolkit]], [[nebula-registry-di]], [[presentation-architecture-risks]], [[presentation-architecture-open-questions]]
status: researched
researched: "2026-07-19"
---

# Presentation Layer — Target/Module Split

Where does the presentation-architecture layer (router, coordinator, navigator, viewmodel-base, presenter) live in the Nebula/Cosmos ecosystem? This answers the owner's second question: *"vale ficar nesse mesmo target desse mesmo projeto, pois a parte de apresentação entre router, navegação, entre diversas outras coisas"* — i.e. does presentation stay in the same Nebula target/project, or split out? Source of truth = root docs + shipped `Package.swift`; this note is synthesis. The architecture pattern itself is [[nebula-presentation-architecture]]; risks in [[presentation-architecture-risks]].

## The central constraint

Nebula's binding rule — **Foundation-only, no `import SwiftUI`/`UIKit`, no `#if canImport(UIKit)`** — is load-bearing. A router/coordinator/presenter layer **inevitably needs SwiftUI** (the routing happens in a `@ViewBuilder`-returning `resolve(route) -> some View`, or a `navigationDestination(for:)` wiring). The question is **which package/target swallows the SwiftUI dependency**. Nebula and Cosmos both currently have `dependencies: []`.

## Industry precedent (2026)

- **pointfreeco/swift-navigation — the canonical Foundation-core + SwiftUI-target split.** 4 products: `SwiftNavigation` (Foundation-only core — `UINavigationPath`/`UIBinding`/`AlertState`/`ButtonState`/`TextState`/`observe`; runs on Linux/Wasm), `SwiftUINavigation` (depends on `SwiftNavigation` + SwiftUI — `sheet`/`alert`/`navigationDestination`), `UIKitNavigation`, `AppKitNavigation`. `import SwiftUINavigation` re-exports `SwiftNavigation` (one-import convenience). `SwiftNavigationTests` depends only on the core (zero SwiftUI in the test graph); `SwiftUINavigationTests` pulls SwiftUI. **No `Router` protocol** — routing is enum-state-driven via case-path bindings. This is the production-grade precedent for option (d).
- **pointfreeco/swift-composable-architecture (TCA) — the single-target anti-pattern.** ONE product/target bundling `Store`/`Reducer`/`TestStore` + SwiftUI/UIKit integration in one module. A reducer file can freely `import SwiftUI`. **Forfeits compile-time layering** — the very thing Nebula wants. TCA is the existence proof that bundling SwiftUI into the logic target loses the boundary.
- **Every other router/coordinator lib** (FlowStacks, CoordinatorKit, RouterKit, SwiftfulRouting, SUICoordinator, SwiftUIFlow, SwiftUIX/Coordinator) — **single SwiftUI target**, no Foundation core. No surveyed library ships a Foundation-only `Router` protocol; the Router abstraction is invariably SwiftUI-coupled (`@ViewBuilder`-returning `resolve`, `any View` destinations).
- **Apple Backyard Birds** (the canonical modular sample) — 3 **separate local SwiftPM packages**: `BackyardBirdsData` (Foundation/SwiftData, no SwiftUI), `LayeredArtworkLibrary` (SwiftUI, deps on Data), `BackyardBirdsUI` (SwiftUI, deps on Data + Library). `BackyardBirdsData` declares NO dep on UI → `import BackyardBirdsUI` from Data is a **hard compile error**. Navigation: `enum AppScreen: Codable, Hashable, Identifiable` + `NavigationStack(path:)` + `.navigationDestination(for:)` — **no Router/Coordinator type**; state via `@Observable` + `@Query`; logic in a `@ModelActor` actor. Apple ships no architecture library.
- **pointfreeco/swift-dependencies** — macro frontend split from macro implementation (so `swift-syntax` is compile-time-only); `DependenciesTestSupport` isolates test-only APIs. Precedent for a future `NebulaTestSupport` product + macro-target split.

## Compile-time enforcement (the Wave H open risk, resolved)

The Wave H risk was: *"single-target Nebula can't enforce the Clean Architecture dependency rule (use cases don't import UI) at compile time."* The enforcement regimes:

1. **Single target (Nebula today)** — `internal` is target-wide, folders are convention only → cannot enforce "use cases don't import UI." **But** "Nebula files don't import SwiftUI" IS trivially enforced because the module doesn't re-export SwiftUI.
2. **Multi-target inside one `Package.swift`** — creates real `.swiftmodule` boundaries + `public`-surface discipline. **BUT** SwiftPM has **no negative dependencies** and does NOT enforce the positive graph by default (SR-1393, open since 2016): it passes `-I` to the shared build dir, so `import SiblingTarget` from a target that never declared it silently compiles if the sibling is built. The opt-in `--explicit-target-dependency-import-check=error` is CLI-only, unreliable via `Package.swift` (`unsafeFlags`), unavailable under `xcodebuild`, and prints errors without failing the build (issue #9431). A SwiftSyntax linter (`SwiftImportChecks`, `nenadvul/solid-like-a-rock` Jun 2026, `Harmonize`) in CI is the within-package mitigation.
3. **Separate local Swift packages** — the **only** regime where undeclared cross-layer `import` is **unconditionally a hard compile error**. A package literally cannot import another package's modules unless the package dep is declared. This is what Backyard Birds and `ModularSPMDemo` do. **Option (d) closes Wave H for free.**

Apple access-level mechanisms: `package` access (SE-0386, one scope per package — can't enforce data↔domain↔presentation *inside* one package); `internal import`/`public import` (SE-0409, Swift 6.0); explicitly-built modules (Xcode 26 default, WWDC25 S245) give the *basis* to diagnose but SR-1393 isn't closed yet.

## Option-by-option

### (a) Foundation-only presentation seams inside Nebula — NO SwiftUI
`NebulaRouter` protocol / `NebulaNavigator` port / `Route` value types / `NebulaViewModel`/`NebulaPresenter` markers, all Foundation-only. App supplies the SwiftUI binding.
- **Deps/identity**: `Nebula` stays `dependencies: []` + Foundation-only. ✅
- **Enforcement**: "no SwiftUI" stays compiler-enforced; internal layering still unenforced (no regression).
- **TDD**: excellent — seams testable in pure Swift, no SwiftUI in the test graph.
- **Hollow?** **Meaningful but narrow.** The `swift-navigation` `SwiftNavigation` core proves Foundation-only nav value types work (`UINavigationPath`/`AlertState`/stack-reduction/deep-link parsing testable without SwiftUI). **BUT** no surveyed library ships a Foundation-only *`Router` protocol that actually routes* — routing happens in the `@ViewBuilder` `resolve` (needs SwiftUI). A `NebulaRouter` that emits `Route` values without producing a `View` is a **navigation-intent bus / value-type event stream** — useful for deep-link parsing, route logging, back-stack reduction, testing route resolution; **hollow if the goal is "the library does navigation for you."** Honest framing: **(a) is the foundation for (d)/(e), not a standalone presentation layer.**
- **`@Observable`**: Observation-module (not SwiftUI), doesn't pull Combine — a `NebulaViewModel` marker *could* conform to `Observable` Foundation-only. But Nebula should NOT ship `@Observable` (Swift 6 friction outside SwiftUI — Donny Wals/Jared Sinclair; consumer concern). A **marker protocol** is the right shape.

### (b) New `NebulaUI` target inside the Nebula package — SwiftUI-bearing
`NebulaUI` target deps on `Nebula` + SwiftUI; `Package.swift` gains a second product.
- **Deps**: package still `dependencies: []` (SwiftUI is a system framework, not an SPM dep). **But** the binding rule "Nebula is Foundation-only" is **violated at the target level** — the package now contains SwiftUI code. ❌ identity.
- **Enforcement**: a `NebulaUI` target DOES protect the Foundation core from SwiftUI within the package (one real win), but SR-1393 means `Nebula` could still `import NebulaUI` transitively without a CI linter.
- **Identity cost**: this is the **TCA compromise**. Works for pointfreeco but breaks Nebula's stated identity. **Rejected.**

### (c) Inside Cosmos — extend Cosmos with presentation architecture
- **Deps**: if the router wires into Nebula's ports/registry, Cosmos gains a dep on Nebula → breaks Cosmos's `dependencies: []`. If self-contained, it's disconnected from Nebula's architecture seams. Either way bad.
- **Conceptual**: Cosmos is a **design system**, not an architecture library. Conflating the two (pointfreeco keeps `swift-navigation` ≠ a design system) muddies Cosmos's identity. **Rejected.**

### (d) New sibling package ("Meridian" / "NebulaFlow" / "CosmosFlow") — SwiftUI presentation architecture, deps on Nebula (+ optionally Cosmos) — **RECOMMENDED**
New package, `dependencies: [.package(name: "Nebula", …)]`, optionally Cosmos. Ships `Router`/`Coordinator`/`Navigator`/`Presenter`/viewmodel-base with SwiftUI bindings.
- **Deps/identity**: Nebula + Cosmos both stay `dependencies: []` + pure. SwiftUI isolated in the new package, where it belongs. ✅ Mirrors `SwiftUINavigation` → `SwiftNavigation` exactly.
- **Enforcement**: **the strongest win.** Nebula-as-a-separate-package **cannot** `import Meridian` — undeclared cross-package import is a hard compile error (SR-1393 only applies within a package's shared `.build`). The "use cases don't import UI" rule becomes compiler-enforced for free. **Only option that fully closes Wave H.** ✅
- **Ergonomics**: `import Meridian` (re-exports `Nebula`); `import Cosmos` for components. Two imports in SwiftUI app targets, one in Foundation-only targets — exactly the swift-navigation ergonomics.
- **TDD**: Foundation-only presentation value types (Route enums, nav-path reducers, deep-link parsers) live in Nebula, test without SwiftUI; SwiftUI-bound routers/coordinators live in Meridian, test with SwiftUI. Mirrors `SwiftNavigationTests` vs `SwiftUINavigationTests`. ✅
- **Cost**: a third package — third `Package.swift`/DocC/CI lane, version coordination (Meridian N ↔ Nebula N ↔ OS N). Real but bounded.
- **Identity**: Nebula = foundation+architecture seams (Foundation-only); Cosmos = design system; Meridian = presentation architecture. **Clean three-way separation.** ✅

### (e) In the app only — Nebula ships Foundation-only seams (a), app owns router/coordinator/viewmodels
- **Deps/identity**: preserved. ✅
- **Enforcement**: none gained (app is one/many targets; convention/lint, not compiler).
- **Ergonomics**: app authors write the router every time; no cross-app reuse without copy-paste.
- **This is Apple's Backyard Birds posture** — Apple ships no router library; the sample uses `AppScreen` enum + `NavigationStack` and the app owns it. Works for Apple because Apple ships **no architecture library at all**. For Nebula — which *is* an architecture library — shipping no presentation code leaves the architecture story incomplete ("use UseCase/Repository/Registry… and then?"). May be intentional (Nebula is a *toolkit of seams*, not an *opinion*), but leaves the gap unfilled. **Holding pattern, not a destination** — natural precursor to (d).

## Recommendation

**Primary — option (d), a new sibling package** ("Meridian" working name). It is the only option that (1) fully closes the Wave H compile-time-enforcement open risk (cross-package import = hard error), (2) mirrors the production precedent (`swift-navigation`), (3) honors every binding rule (Nebula + Cosmos stay `dependencies: []` + pure), (4) gives the cleanest TDD story (Foundation-only value types in Nebula test without SwiftUI; SwiftUI routers in Meridian test with SwiftUI). SwiftUI is isolated where it belongs.

**Fallback / holding pattern — option (a)+(e)**: if the maintenance budget for a third package isn't available *now*, ship the Foundation-only seams (`NebulaRouter`/`NebulaNavigator`/`Route`/`NebulaViewModel` marker) inside Nebula and document the recommended SwiftUI binding pattern for the app. Preserves identity + `dependencies: []` at the cost of: the router abstraction is narrow (navigation-intent bus, not a full router), Wave H stays open, app authors write boilerplate. **This is the natural precursor to (d)** — the seams designed for (a) move into Meridian's Foundation core when (d) is justified.

**Reject (b)** (violates "Nebula is Foundation-only" at the target level, TCA compromise, SR-1393 leakage) **and (c)** (conflates Cosmos's design-system identity; breaks Cosmos `dependencies: []` or disconnects from Nebula seams).

## The real trade-off (for the owner)

**NOT** the binding-rule tension — option (d) honors it cleanly. The real trade-off is **maintenance budget for a third package vs. completeness of the architecture story**:
- **(d)** — architecturally correct, matches precedent, compiler-enforces the dependency rule (closes Wave H). Cost: third package to maintain / version-coordinate (Meridian N ↔ Nebula N ↔ OS N) / document / CI.
- **(a)+(e)** — low-maintenance holding pattern: Nebula stays single-package, ships Foundation-only seams, app owns SwiftUI routing. Cost: incomplete architecture story + Wave H open until a third package is justified.

If the ecosystem is meant to be a **complete** architecture toolkit (the CLAUDE.md "Clean Architecture toolkit seams" framing), **(d) is the consistent answer**. If Nebula is intentionally a **toolkit of seams** and the app always owns the driving adapter, **(a)+(e) is the honest answer** (Backyard Birds precedent). The decision is framed for the owner in [[presentation-architecture-open-questions]].
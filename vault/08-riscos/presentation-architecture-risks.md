---
tags: [riscos, architecture, presentation, swiftui, swift6, nebula]
aliases: [presentation architecture risks, NebulaUI risks, router risks]
related: [[nebula-presentation-architecture]], [[nebula-presentation-target-split]], [[presentation-architecture-open-questions]], [[nebula-swift6-concurrency]], [[nebula-test-doubles]]
status: researched
researched: "2026-07-19"
---

# Presentation Architecture — Consolidated Risks

Risks for the presentation-architecture decision ([[nebula-presentation-architecture]]) and the target split ([[nebula-presentation-target-split]]), most-severe first. Source of truth = root docs; this note is synthesis. Open decisions in [[presentation-architecture-open-questions]].

## 1. TCA structurally rejects Nebula's DI (and has Swift 6 sharp edges)
TCA's `@Dependency` is a **global-default + scoped-override** model (`DependencyKey`/`DependencyValues`/`withDependencies`), NOT constructor injection. pointfreeco explicitly says "`@Dependency` is not a replacement for general-purpose DI systems." To plug in `NebulaFakeRepository`/`NebulaStubUseCase`/`NebulaSpyUseCase` you must wrap each port in a `DependencyKey` with `liveValue` + `testValue` (`unimplemented`) — adapting Nebula TO TCA, not flowing with it. Plus: documented `@Reducer`/`@ObservableState` macro-isolation trap (no clean `nonisolated` reducer workaround); TestFlight-only `EXC_BAD_ACCESS` on TCA 1.17.1 needing `SWIFT_VERSION = 6.0`; TCA 1.23.2 broke on Xcode 26.4 (Issue #3917). **Mitigation**: TCA is OUT under `dependencies: []` anyway — but even as inspiration, the `@Dependency` DI model is the wrong shape for Nebula; the TestStore pattern is the only transferable idea. Adopt MVVM (constructor injection) instead.

## 2. SR-1393 — SwiftPM doesn't enforce the positive import graph
Open since 2016. SwiftPM passes `-I` to the shared build dir → `import SiblingTarget` from a target that never declared it **silently compiles** if the sibling is built. `--explicit-target-dependency-import-check=error` is CLI-only, unreliable via `Package.swift` (`unsafeFlags`), unavailable under `xcodebuild`, prints without failing (issue #9431). **Impact**: a multi-target-in-one-package split (option b) does NOT bulletproof the Foundation-only core — `Nebula` could `import NebulaUI` transitively. **Mitigation**: separate **packages** (option d) — SR-1393 only applies within a package's shared `.build`; cross-package undeclared import is a hard error. Or a SwiftSyntax CI linter (`SwiftImportChecks`, `nenadvul/solid-like-a-rock` Jun 2026, `Harmonize`) for within-package enforcement.

## 3. `@Observable` outside SwiftUI has Swift 6 friction
`@Observable` is Observation-module (SE-0395), NOT SwiftUI, doesn't pull Combine — so a `NebulaViewModel` marker *could* conform to `Observable` in a Foundation-only target. **But** using `@Observable` outside SwiftUI under Swift 6 has real friction: `withObservationTracking`'s `onChange` is `@Sendable` + one-shot + `willSet` semantics (old value, not new); capturing non-Sendable `self` errors; `@MainActor` isolation conflicts with the `@Sendable` closure (Donny Wals, Jan 2025). Jared Sinclair (Sep 2025): Apple "softly deprecated" Combine/`ObservableObject` but only *partially replaced* it; `withObservationTracking` is one-shot/no cancellation; the `Observations` AsyncSequence (iOS 26 / Swift 6.2) is not back-ported and has a reported dropped-events bug (swiftlang/swift#84954). **Mitigation**: Nebula ships a **marker protocol** `NebulaViewModel`, NOT `@Observable`. The `@Observable` conformance lives in the consumer (app / Meridian), where SwiftUI's synchronous invalidation path handles it. This is consistent with Nebula's "no SwiftUI, app supplies its own `@Observable`" stance.

## 4. `NavigationStack` is reportedly broken on macOS
Dave DeLong (Jan 2026): "absolutely broken SwiftUI `NavigationStack`, especially on macOS. You can't look up if the path already contains a destination value. You can't manipulate or reorder `NavigationPath`… utterly unusable, even after four years." **Mitigation**: this is *evidence for* the Foundation-only core (option a/d) — modeling navigation in a UI-free typed `[Route]` stack (testable, manipulable) is defensive against the SwiftUI primitive's unreliability. Prefer a **typed `[Route]` array** over type-erased `NavigationPath` (you can inspect/reorder it); push identifier values not full models.

## 5. FlowStacks has an open iOS 26 infinite-loop regression
FlowStacks 0.8.4, `swift-tools: 5.10`, low velocity. Issue #103 (opened Aug 2025, updated Feb 2026): deep back navigation in TabView + FlowStacks coordinator triggers an infinite loop; workaround `FlowStack($coordinator.routes, withNavigation: true)` instead of wrapping in an outer `NavigationStack`. Swift 6/Sendable status **unverified**. **Mitigation**: FlowStacks is OUT under `dependencies: []` anyway; don't ape its `FlowPath` API. Use native `NavigationStack` + typed `[Route]`.

## 6. The "Foundation-only Router is hollow" critique
A `NebulaRouter` protocol that emits `Route` values without ever producing a `View` is a **navigation-intent bus / value-type event stream**, not a router — because actual routing happens in a `@ViewBuilder`-returning `resolve(route) -> some View` (needs SwiftUI). No surveyed library ships a Foundation-only `Router` protocol that routes. **Mitigation**: the critique *collapses* if the Foundation core holds a **typed path/stack of `Route` values** (not a bare `@Sendable (Route) -> Void` closure) — then it's a real navigation model (deep-link parsing, back-stack reduction, route logging, testable route resolution) and the SwiftUI adapter just renders it. Frame option (a) honestly as "Foundation-only **seams** + a navigation **model**," not "a router that routes." The `swift-navigation` `SwiftNavigation` core (`UINavigationPath`/`AlertState`/`ButtonState` value types) is the precedent.

## 7. `@MainActor` parallelism tax in tests
Every `@Observable`-based viewmodel is `@MainActor` → tests touching it must be `async` and run on the main actor, **blocking parallel test execution**. **Mitigation**: keep only the thin UI-facing layer `@MainActor`; push heavy logic into non-isolated `NebulaUseCase` bodies (run off-actor, return `Sendable` results). The VIPER Interactor is the only naturally non-isolated parallel-testable layer — a reason VIPER is the structural reference even though MVVM is the shipping default.

## 8. Snapshot tests as a TDD tool (smell)
Snapshot tests are **regression tools, not TDD tools** — brittle, CI-sensitive, slow, unsuitable for red-green. If you need snapshots to test viewmodel *behavior*, the architecture is wrong (logic not extracted). **Mitigation**: push logic into testable layers (viewmodel/reducer/interactor), keep `View`s pure functions of state. Snapshots only for `View` visual regression across OS point releases, and sparingly. Nebula has no UI → no snapshot tests in Nebula itself (binding rule: no UI snapshots in `NebulaTests`).

## 9. Test-hostile patterns to ban
- **`@Environment`-injected Coordinators/Routers** — global state, no constructor injection, requires View rendering / `EnvironmentValues` reflection to test. Avoid; use constructor injection.
- **`@ViewBuilder` Coordinators returning `_ConditionalContent`** — opaque types untestable without ViewInspector/snapshots (Manferdini's article is *about* this pitfall). Use typed `[Route]` arrays instead.
- **Singletons / `static var shared` services** — fight `NebulaRegistry`/constructor injection; require `Mutex<Nebula*Config>` `set(_:)` to test (brittle).
- **Reflection-based View testing (ViewInspector) as primary confidence** — gap-filler, not a TDD tool; if it's primary, the architecture is wrong.
- **Fire-and-forget `Task` in `init`** (any architecture) — non-deterministic async tests; surface asynchronicity through `async` functions that complete (Swift Forums). Use `.task` over bare `Task` (auto-cancellation, inherits isolation); avoid `Task.detached` in views.

## 10. SwiftUI navigation footguns (2026)
`@State` is NOT autoclosure-deferred like `@StateObject` — `@State private var vm = HeavyViewModel()` runs init on every body recomputation until SwiftUI commits storage (use optional + `.task` hydration for expensive init). Don't mutate `@Observable` state inside `body` ("Modifying state during view update"). Re-owning an already-owned `@Observable` in `@State` resets it (source-of-truth bug — use `let`/`@Bindable` for passed-down). `List`/`ForEach` `$item` doesn't compile (iterator is `let`) — `@Bindable var item = item` shadow. `@MainActor @Observable` init from a non-isolated `App`/`View` fails to compile — isolate the owner or adopt SE-0466. `NavigationPath` type-erasure loses exhaustive handling + `Codable` requires every pushed value `Codable`. Don't mix `NavigationLink(destination:)` (view-driven) with programmatic `NavigationPath`. Don't share one `NavigationPath` across tabs. SwiftUI `Shape.path`/`Layout`/`visualEffect`/`onGeometryChange` run off-main → capture value copies in capture lists, don't send `self`.

## 11. `presentationContentShape` is NOT a new OS 26 API
The morphing presentation API in OS 26 is `.navigationTransition(.zoom(sourceID:in:))` + `.matchedTransitionSource(id:in:)` (WWDC25 S323), NOT a new `presentationContentShape`. `presentationContentShape(_:)` exists since iOS 16.4 for hit-testing. **Mitigation**: don't cite a nonexistent 2026 API; use the zoom/morph transitions for Liquid Glass presentations.

## 12. Third-package maintenance + version coordination (option d cost)
A new sibling package (Meridian) means a third `Package.swift`/DocC catalog/CI lane and version coordination (Meridian N ↔ Nebula N ↔ OS N). **Mitigation**: bounded cost; mirror `swift-navigation`'s structure. If the budget isn't available now, ship option (a)+(e) as the holding pattern (the seams designed for (a) move into Meridian's Foundation core later).

## Sources (canonical)
- TCA: Discussions #2802/#2218/#1533/#3606/#3672, Issue #3917, dev.to macro-isolation trap, Swift Forums `@Dependency` non-TCA DI.
- swift-navigation: repo + Package.swift (Foundation-core + SwiftUI-target split); swift-url-routing (Foundation-only).
- Donny Wals (Jan 2025) + Jared Sinclair (Sep 2025) on `@Observable` outside SwiftUI; swiftlang/swift#84954 (`Observations` dropped-events).
- Dave DeLong (Jan 2026) on `NavigationStack` broken on macOS (mjtsai aggregation).
- FlowStacks Issue #103 (iOS 26 infinite loop).
- SR-1393 (swift-package-manager#5297); issue #9431; `SwiftImportChecks`; `nenadvul/solid-like-a-rock`; `Harmonize`.
- SE-0395 (Observation), SE-0466 (default actor isolation), SE-0475 (`Observations`), SE-0386 (`package` access), SE-0409 (`internal import`/`public import`).
- Apple Backyard Birds sample (3 separate local packages, enum `AppScreen` + `NavigationStack`, no Router type).
- Manferdini "From broken to testable SwiftUI navigation" (`@ViewBuilder`/`_ConditionalContent` pitfall).
- WWDC25 S266 (concurrency in SwiftUI), S323 (new design / zoom transitions), S245 (explicitly built modules); WWDC26 S269 (`@State` macro), S8006 (SwiftUI architecture-agnostic).
Full URL list in the agent transcripts.
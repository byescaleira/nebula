---
tags: [padroes, architecture, presentation, swiftui, router, meridian, nebula]
aliases: [Meridian, Meridian Router, Nebula Observable Router, MeridianNavigationStack]
related: [[nebula-presentation-seams]], [[nebula-presentation-architecture]], [[nebula-presentation-target-split]], [[presentation-architecture-risks]], [[presentation-architecture-open-questions]], [[nebula-swift6-concurrency]]
status: shipped
shipped: "2026-07-19 (Wave II)"
---

# Meridian — the `@Observable Router` (Wave II — shipped)

The SwiftUI-bearing sibling of Nebula. Where [[nebula-presentation-seams]] ships the Foundation-only **navigation model** (`NebulaRoute` / `NebulaNavigationStack` / `NebulaRouter` / `NebulaSpyRouter` / `NebulaViewModel`), Meridian ships the `@Observable` concrete `Router` + the `NavigationStack` wiring that render it. Source of truth = `Meridian/Sources/Meridian/`; this note is synthesis. On conflict, root doc/code wins.

## What shipped (2 symbols)

| Symbol | Shape | Role |
|---|---|---|
| `Router<Route: NebulaRoute>` | `@MainActor @Observable final class`, `: NebulaRouter<Route>` | The data-driven navigation owner per tab/flow. Owns the observation-tracked `var path: [Route]`; intent methods (`push`/`pop()`/`pop(_:)`/`popToRoot`/`replaceStack`) delegate to `NebulaNavigationStack` statics — single source of truth shared with the pure-Swift model. `Sendable` by `@MainActor` isolation (no `@unchecked`). |
| `MeridianNavigationStack<Route, Root, Destination>` | `struct: View` | `NavigationStack(path: $router.path)` + `navigationDestination(for: Route.self)` with a `@ViewBuilder` destination resolver — the type-driven view factory. One per tab. |

## Package structure (the (d) split, executed)

- **Separate local SwiftPM package** at `Meridian/` in the nebula repo, with its own `Package.swift` (`swift-tools-version: 6.3`, language mode v6, all 5 platforms `.v26`, `defaultLocalization: en`).
- `dependencies: [.package(name: "Nebula", path: "../")]` — the local Nebula sibling. SwiftUI is a system framework (not an SPM dep), so `dependencies` lists only Nebula → Meridian stays third-party-free.
- `.target(name: "Meridian", dependencies: [.product(name: "Nebula", package: "Nebula")], exclude: ["Meridian.docc"])` — the DocC catalog excluded so `swift build` is warning-clean (mirrors Nebula); `xcodebuild docbuild` builds the catalog.
- One repo, one CI lane builds both: `swift build` at root = Nebula only (the nested `Meridian/Package.swift` is NOT recursed); `swift build` in `Meridian/` resolves Nebula via `../` + builds Meridian. Two independent module graphs.
- **Promoting Meridian to its own git repo for public consumption is a documented future step** (the `path: "../"` becomes a git URL). The enforcement benefit comes from a **separate package** (separate module graph), not a separate repo — so the monorepo subdir delivers the architecture + compile-time enforcement now without a third-repo ceremony.

## The compile-time enforcement (the Wave H closer — proven)

The root `swift build` builds **only Nebula** (its `Package.swift` has `dependencies: []`); it never resolves or builds Meridian. Because Nebula declares no dependency on Meridian, `import Meridian` from any `Sources/Nebula/*.swift` is an **unconditional hard compile error** ("no such module 'Meridian'") — the "use cases / domain never import presentation" Clean Architecture rule is compiler-enforced. SR-1393 (SwiftPM doesn't enforce the positive import graph) only applies **within one package's** shared `.build`; cross-package undeclared import is a hard error regardless of repo. This is the only regime that closes Wave H for free. ([[nebula-presentation-target-split]] option (d).)

## Why the port is `async` (the Swift 6 conformance fix)

`Router` is `@MainActor @Observable` (Sendable by isolation — `@Observable` + a mutable `var path` needs `@MainActor` to be Sendable without `@unchecked`, which Meridian never authors). But `NebulaRouter` (Nebula) is **nonisolated** (binding rule: Nebula takes no `@MainActor`, app supplies isolation). A synchronous `@MainActor` method **cannot** satisfy a nonisolated sync requirement — the Wave II build caught this ("main actor-isolated instance method cannot satisfy nonisolated requirement"). Fixes considered:
- `@MainActor` on `NebulaRouter` ❌ — violates the binding rule (Nebula stays nonisolated; would force the spy to `@MainActor`, breaking cross-task test sharing).
- SE-0411 isolated conformances ❌ — experimental, above the Nebula 26 floor (SE-0470).
- **Async port ✅** — a synchronous `@MainActor` method **witnesses a nonisolated `async` requirement** (the `await` performs the actor hop). The on-actor `Router` conforms; Nebula stays nonisolated. The async port is ALSO the **cross-actor bridge**: an off-actor deep-link parser can `await router.replaceStack(with:)` to drive the on-actor router — exactly the deep-link-as-data story. Conformers keep **sync** impls (a sync method witnesses an async requirement; no hop for nonisolated sync, an actor hop for isolated) — concrete calls (`router.push(.x)`) stay synchronous; only `any NebulaRouter` calls `await`.

This is the canonical Swift 6 idiom for an actor-isolated implementation of a nonisolated protocol — verified by a clean build ([[ci-warning-masking-and-inference-fragility]]: verified with `rm -rf .build`).

## `@Observable` + `@MainActor` details

- `@MainActor @Observable public final class Router<Route: NebulaRoute>: NebulaRouter<Route>` — attribute order matters (`@MainActor @Observable` BEFORE `public`; the other order is a parse error).
- `var path: [Route]` is observation-tracked; `MeridianNavigationStack` binds `NavigationStack(path: $router.path)` via `@Bindable var router = router` (the 2026 shadow-in-body idiom).
- Intent methods delegate to `NebulaNavigationStack.push(_:into:)` etc. — mutating `path` through the `@Observable` accessor triggers observation (`withMutation`), so `NavigationStack` updates on push/pop. Single source of truth: the same `static` helpers the pure-Swift `NebulaNavigationStack` instance API uses.
- `Router` is `Sendable` by `@MainActor` isolation (a `@MainActor final class` is Sendable) — satisfies `NebulaRouter: Sendable` without `@unchecked`.

## TDD fit (Meridian half)

- `Router` is testable **as data**: `let router = Router<R>(); router.push(.x); #expect(router.path == [.x])` — no spy needed for the on-actor viewmodel (the concrete router IS the test double; assert `path`). The `NebulaSpyRouter` ([[nebula-presentation-seams]]) is for off-actor/Sendable intent flows.
- The port-conformance test (`await port.push(...)` through `any NebulaRouter<R>`) verifies the async hop reaches the `@Observable` wrapper.
- `@MainActor` test suite — Router tests are `@Suite @MainActor` (constructing `Router` requires the main actor). The `@MainActor` parallelism tax ([[presentation-architecture-risks]] #7) is bounded: only the thin presentation layer is `@MainActor`; heavy logic stays in non-isolated `NebulaUseCase` bodies.

## What is NOT in Wave II (deferred)

- Type-driven `Optional<Destination>` enum destinations + deep-link parser pattern + `MeridianExample` executable → Wave III.
- ADR + version coordination (Meridian N ↔ Nebula N ↔ OS N) + per-platform `xcodebuild` gate + public DocC build → Wave IV.

## Build gate (Wave II)

- Root Nebula: `rm -rf .build && swift build && swift test && swift build -c release` → 525 tests / 110 suites, zero warnings, release clean.
- Meridian: `swift build && swift test && swift build -c release` → 6 tests / 1 suite, zero warnings, release clean.
- Enforcement proof: root build is Meridian-free (Nebula `dependencies: []`); `import Meridian` from Nebula = hard error (structural).
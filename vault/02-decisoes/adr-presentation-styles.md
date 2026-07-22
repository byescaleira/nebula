---
tags: [decisoes, adr, architecture, presentation, navigation, swiftui, nebula]
aliases: [ADR presentation styles, ADR Wave N20, NebulaPresentationStyle ADR, per-route presentation style]
related: [[nebula-presentation-architecture]], [[nebula-presentation-seams]], [[nebula-meridian-router]], [[nebula-presentation-target-split]], [[nebula-clean-architecture-toolkit]]
status: accepted
date: "2026-07-22"
wave: "N20"
release: "Nebula 0.18.0"
---

# ADR — Per-route presentation styles + modern container adapters (Wave N20)

## Context

The Wave I/II presentation architecture shipped a Foundation-only navigation **model + port** (`NebulaRoute` / `NebulaNavigationStack<Route>` / `NebulaRouter<Route>` / `NebulaSpyRouter` / `NebulaViewModel`) and the Meridian SwiftUI adapter (`@MainActor @Observable Router<Route>` + `MeridianNavigationStack`). Two gaps remained that the owner wanted closed:

1. **The router only had `push`** — no sheet / full-screen cover. The owner wants to **choose per screen** how a route is presented (push vs sheet vs full-screen cover).
2. **Only `NavigationStack`** shipped — no split view or tab view. The owner wants the modern container trio (`NavigationStack` + `NavigationSplitView` + `TabView`) bound to the router, pickable per screen area. (`NavigationView` is deprecated since iOS 16 — `NavigationSplitView` subsumes it.)

## Decision

Extend the existing Wave I/II pattern verbatim (model + statics + port + spy in Nebula; `@Observable` wrapper + SwiftUI adapter in Meridian) — **additive, non-breaking**. Ships as **Nebula 0.18.0** (additive minor within Nebula 26); Meridian tracks.

**Per-route style is the dispatch key — an enum on the route, not a modal-state-per-feature map.** A route declares `presentationStyle: NebulaPresentationStyle` (`.push`/`.sheet`/`.fullScreenCover`); `present(_:)` dispatches by the declared style; `present(_:as:)` overrides at the call site. The route stays the single source of "how I'm presented," and the same route can push in one flow and sheet in another.

**`NebulaPresentationRouter` is a sub-protocol of `NebulaRouter`, not a replacement.** Existing push-only `NebulaRouter` conformers are untouched; the spy and the Meridian `Router` opt into the richer port.

**Single source of truth reused.** `NebulaPresentation<Route>` owns the push path **and** a single modal slot; present/dismiss live in `static` `inout`-component helpers; the Meridian `@Observable Router` delegates to the same statics (the `NebulaNavigationStack`-statics precedent extended to the modal layer). Push-path ops delegate verbatim to `NebulaNavigationStack` (no duplicated stack logic).

**`.sheet(isPresented:)` / `.fullScreenCover(isPresented:)`, NOT `.sheet(item:)`.** `Route` is `Hashable` but not `Identifiable`, and Nebula can't force `Identifiable` on the app's route enum. The two gated `isPresented` bindings are mutually exclusive (single `presented` slot + `presentedStyle` picks the container).

**`fullScreenCover` is unavailable on macOS** → gated `#if !os(macOS)` with a `.sheet` fallback on macOS (graceful — macOS has no full-screen cover surface); the other 4 platforms use the dedicated cover.

**Modern trio only** — `NavigationStack` (push) + `NavigationSplitView` (split, subsumes the deprecated `NavigationView`) + `TabView` (`Tab(value:)`, one `Router` per tab — never share a path across tabs). `Tab: CaseIterable & Hashable & Sendable` so `MeridianTabView` iterates `allCases` wrapping each in `Tab(value:)` for a real tab bar.

## Consequences

- **Additive, non-breaking** — `NebulaRouter`/`NebulaNavigationStack`/`MeridianNavigationStack(router:root:destination:)` existing API preserved; `NebulaRoute.presentationStyle` has a `.push` default so existing conformers auto-conform; `NebulaPresentationRouter` is a sub-protocol so existing `NebulaRouter` conformers unbroken.
- **Nebula stays Foundation-only** — zero `import SwiftUI`/`UIKit` in Nebula (grep-verified); all SwiftUI lives in Meridian; `dependencies: []` pristine (the cross-package boundary still enforces the dependency rule — `import Meridian` from Nebula is a hard compile error).
- **`Sendable` derived throughout** — no `@unchecked` on any Nebula value type; the spy keeps `final class` + `let Mutex` derived-Sendable; the Meridian `Router` is `Sendable` by `@MainActor` isolation.
- **No `@available` gate** — `NavigationSplitView` (iOS 16/macOS 13), `Tab(value:)` (iOS 18/macOS 15), `.sheet`/`.fullScreenCover` are all below the `.v26` floor.
- The per-feature `Optional<Destination>` enum → `sheet(item:)` pattern (the earlier "Wave III sheet" hint) still coexists — for alerts / non-route modals; per-route style is for navigation-adjacent sheets/covers.

## Status

**Accepted + Implemented** (Nebula 0.18.0, 2026-07-22). 985 Nebula tests / 198 suites + 20 Meridian tests / 3 suites green; zero concurrency warnings; release clean; all 5 platforms compile the new Nebula types ungated; DocC `BUILD DOCUMENTATION SUCCEEDED`. Root-doc governance: `DECISIONS.md` N20 ADR row; `CHANGELOG.md` 0.18.0 entry; `ROADMAP.md` Done (0.18.0); `ARCHITECTURE.md` presentation subtree + Meridian prose; `ArchitecturePresentation.md` + `Meridian.md` DocC. Tagging deferred to the owner's gate decision. See [[nebula-presentation-architecture]] (Wave N20 — shipped section).
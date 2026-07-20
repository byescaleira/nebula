---
tags: [riscos, os, oslog, availability, visionos, macos, gating]
aliases: [visionOS OSLogStore.Scope uncertain, OSLogStore.Scope visionOS]
related: [[Home]], [[nebula-logging]]
status: open
---

# visionOS availability of `OSLogStore.Scope` is uncertain

Gotcha: visionOS availability of `OSLogStore.Scope.system` and `.local()` is **UNCERTAIN**. The `Store.h` header does NOT list visionOS in `API_UNAVAILABLE`, but that absence is not proof of availability — it may simply be an undocumented gap. Source of truth = the OSLog clang header / `.swiftinterface`; this note is synthesis.

## Safe treatment

Treat `OSLogStore.Scope.system` / `.local()` as **macOS-only** by safe gating:

- `#if os(macOS)`, OR
- explicit per-platform `@available(<platform>, unavailable)` that **includes visionOS** (e.g. `@available(visionOS 26, unavailable)` alongside `iOS`/`tvOS`/`watchOS`).

Never gate this with `@available(macOS 12, *)` alone — its `*` fallback enables ALL platforms including visionOS. See the binding rule on per-platform unavailable gates in `CLAUDE.md`.

## Confirmation step

Confirm at compile time on the visionOS SDK before un-gating. This mirrors the `#if !os(<platform>)` precedent established by `NebulaNotifications` (see [[nebula-notifications]]): for SDK symbols `API_UNAVAILABLE` on a platform, only `#if !os(<platform>)` compiles; `@available(unavailable)` and `if #available(*)` are both empirically invalid. Here the symbol is NOT marked unavailable on visionOS, so the conservative move is the opposite — assume unavailable and gate it out until proven otherwise.
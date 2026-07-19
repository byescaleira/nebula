---
tags: [padroes, architecture, presentation, swiftui, deeplink, router, meridian, nebula]
aliases: [Nebula deep link, type-driven destinations, Meridian destinations, impossible states unrepresentable]
related: [[nebula-meridian-router]], [[nebula-presentation-seams]], [[nebula-presentation-architecture]], [[presentation-architecture-risks]], [[presentation-architecture-open-questions]]
status: shipped
shipped: "2026-07-19 (Wave III)"
---

# Type-Driven Destinations + Deep-Link-as-Data (Wave III — shipped)

The two patterns the `Router` + `MeridianNavigationStack` ([[nebula-meridian-router]]) foundation enables: **deep links as data** and **type-driven modal destinations** ("impossible states unrepresentable"). Wave III ships a runnable `MeridianExample` executable (living docs + compile gate) and tests proving both patterns are unit-testable without a simulator. Source of truth = `Meridian/Sources/MeridianExample/` + `Meridian/Tests/MeridianTests/DeepLinkTests.swift`; this note is synthesis.

## Pattern 1 — deep link as data

A deep link is a **pure function `URL → [Route]`**. Parse the URL into a typed `[Route]`, then `router.replaceStack(with:)`. Assertable as a value:

```swift
#expect(DeepLink.parse(URL(string: "nebula://app/detail/\(id)/settings")!)
        == [.root, .detail(id: id), .settings])
```

- The parser is **app code** (Meridian ships the MODEL it produces — `NebulaRoute`/`[Route]` — not the app-specific parser). Nebula stays Foundation-only; the parser lives in the example/app.
- The async `NebulaRouter` port ([[nebula-presentation-seams]]) is the **cross-actor bridge**: a non-MainActor deep-link service can `await router.replaceStack(with:)` to drive the `@MainActor` router. In the example (on-actor `onOpenURL`), the plain `Task {}` inherits `@MainActor`, so the concrete sync `replaceStack` is called directly — no `await` (the async form is for off-actor callers).
- **State restoration** is the same idea via `Codable`: `Route: NebulaRoute` is `Codable`, so `router.path` round-trips (tested in Wave II's `codableRoundTrip`).
- `replaceStack` is the deep-link primitive (not push): deep links replace the whole stack ("parse → `popToRoot` → append/replace"), so back-navigation from a deep-linked destination goes to root, not to an arbitrary prior state.

## Pattern 2 — type-driven modal destinations

Model each feature's sheet/alert destination as a single `Optional<Destination>` enum. Only one destination is active → "edit sheet AND delete alert showing" is a state the **compiler refuses** (no `editItem && confirmDelete`). This is the pointfree swift-navigation idea, **natively** — no `@CasePathable` macro (`dependencies: []`):

```swift
@MainActor @Observable
final class ItemListViewModel: NebulaViewModel {
    var destination: Destination?      // single optional — one active
    func edit(_ id: UUID) { destination = .editItem(id) }
    func confirmDelete(_ id: UUID) { destination = .confirmDelete(id) }
    func dismiss() { destination = nil }
}

enum Destination: Identifiable {
    case editItem(UUID)
    case confirmDelete(UUID)
    var id: String { switch self { case .editItem(let id): "edit-\(id)"
                                   case .confirmDelete(let id): "delete-\(id)" } }
}

.sheet(item: $vm.destination) { destination in
    switch destination { case .editItem(let id): EditSheet(id: id)
                          case .confirmDelete(let id): ConfirmDeleteSheet(id: id) }
}
```

- `sheet(item:)` requires `Identifiable`; the enum hand-rolls `id` per case (a stable, distinct `String`). `@CasePathable` would give per-case bindings (`$vm.destination.editItem`); without it, the single optional + `switch` delivers ~90% of the value — the "only one active" guarantee is pure Swift (the optional enum), not a macro.
- For deep drill-down `NavigationStack` flows, the typed `[Route]` stack handles recursion (Wave I/II); the enum-destination layer handles **modals**. The two layers compose: the stack is the push hierarchy, the optional enum is the modal hierarchy.
- `replaceStack`/`push` never take a full model — push **identifier values** (`.detail(id:)`); the destination view loads its own data from the identifier ([[presentation-architecture-risks]] #10 footgun).

## What shipped (Wave III)

| Artifact | Path | Role |
|---|---|---|
| `MeridianExample` executable target | `Meridian/Sources/MeridianExample/MeridianExampleApp.swift` | Runnable demo: `Router<AppRoute>` + `MeridianNavigationStack` + `Destination` enum sheet + `onOpenURL` deep link. `@main App`; compiles = gate; `swift run MeridianExample` launches the macOS app. NOT a shipped product. |
| `DeepLinkTests` | `Meridian/Tests/MeridianTests/DeepLinkTests.swift` | Deep-link parse → `[Route]` assertions + `replaceStack` via the async port; `Destination` `Identifiable` + single-optional tests. 7 tests. |
| `NavigationPatterns` DocC | `Meridian/Sources/Meridian/Meridian.docc/NavigationPatterns.md` | Living docs for both patterns. |

## TDD fit (Wave III)

- Deep links are pure functions → `#expect(DeepLink.parse(url) == [.root, .detail(id:)])` — no simulator, no `View` rendering. The whole deep-link surface is unit-testable.
- Modal destination state is a value (`Optional<Destination>`) → `#expect(vm.destination == .editItem(id))`, `#expect(vm.destination == nil)` after `dismiss()`.
- The example `@main App` is a **compile gate**, not a test target — it proves the full pattern composes (Router + NavigationStack + sheet + deep link) under real SwiftUI. Its pieces (parser, destination enum) are unit-tested via self-contained copies in `DeepLinkTests` (the executable target isn't importable).

## Notes / guardrails

- One `Router`/`MeridianNavigationStack` per tab — never share a path across tabs ([[presentation-architecture-risks]] #10).
- The example `onOpenURL` uses `Task { router.replaceStack(...) }` (no `await`) because the `Task` inherits the SwiftUI action's `@MainActor`. From a non-MainActor context, use `await router.replaceStack(...)` via the async port (the cross-actor bridge).
- `@CasePathable` is deliberately NOT adopted (`dependencies: []`). If per-case bindings become worth it later, it's an app-level macro, not a Meridian dep.

## Build gate (Wave III)

- Meridian: `swift build && swift test && swift build -c release` → 13 tests / 3 suites (Router 6 + DeepLink 5 + Destination 2), zero warnings, release clean (incl. `MeridianExample` executable).
- Root Nebula: unchanged from Wave II (525 tests).
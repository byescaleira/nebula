---
tags: [padroes, architecture, presentation, navigation, deeplink, universal-links, useractivity, shortcuts, notifications, swiftui, nebula]
aliases: [Nebula deep links, Nebula external navigation, NebulaLink, NebulaLinkParser, NebulaLinkRouter, Wave N21]
related: [[nebula-presentation-architecture]], [[nebula-presentation-seams]], [[nebula-meridian-router]], [[nebula-presentation-destinations-deeplink]], [[nebula-swift6-concurrency]], [[nebula-test-doubles]], [[adr-deep-links]]
status: shipped
researched: "2026-07-22"
shipped: "2026-07-22 (Wave N21 — Nebula 0.19.0)"
---

# Nebula External Navigation Entries (deep links, universal links, UserActivity, + app-constructed)

The **external navigation** half of the presentation architecture: a Foundation-only seam that funnels **every** external navigation entry — deep links, universal links, Spotlight/Handoff/Siri, Home-screen shortcuts, notification taps, in-app "go here" — through one normalized value, one app-provided parser port, and one router glue, so they all conform to the same `NebulaPresentationRouter`. Source of truth = root docs (`ARCHITECTURE.md`, `DECISIONS.md`) + shipped `Sources/Nebula/Architecture/Presentation/`; this note is synthesis. On conflict, root doc/code wins. Canonical hub for external navigation; the presentation model it conforms to is [[nebula-presentation-architecture]]; the Meridian sibling is [[nebula-meridian-router]]; the ADR is [[adr-deep-links]].

## The problem

Before Wave N21 the only navigation entry wired into the router was **ad-hoc**: `MeridianExampleApp` hand-rolled a `DeepLink.parse(_ url: URL) -> [Route]` function hooked via `.onOpenURL { url in Task { itemsRouter.replaceStack(with: DeepLink.parse(url)) } }` (Wave III, 0.3.0). It was custom-scheme only (`nebula://`), lived in the example app, had no Nebula abstraction, no test doubles, and no story for universal links, `NSUserActivity`, shortcuts, or notifications. The owner asked that "every form of external navigation conform to the router."

## The pipeline — normalize → resolve → apply

```
external event ──► NebulaLink (Sendable) ──► NebulaLinkParser<Route> ──► NebulaLinkDestination<Route>
                                                                          │
                                          NebulaLinkRouter<Router>.open ──► await router.apply(destination)
                                                                                     │
                                          NebulaPresentationRouter.apply(_:)  (additive default extension)
```

### 1. Normalize — `NebulaLink`

A `Sendable`/`Equatable`/`Hashable` struct normalizing any external-navigation event:

- `source: NebulaLink.Source` — `.urlScheme` / `.universalLink` / `.userActivity` / `.shortcut` / `.notification` / `.programmatic`.
- `url: URL?` / `identifier: String?` / `title: String?` / `payload: [String: String]`.
- `init(url:)` — infers `.universalLink` for `http`/`https` (case-insensitive), else `.urlScheme`; nil-scheme-safe (a `URL` built via `URLComponents` with no scheme still resolves to `.urlScheme`).
- `init(source:url:identifier:title:payload:)` — the full form (used for the app-constructed sources).

**The non-Sendable Apple classes that originate these events (`NSUserActivity`, `UIApplicationShortcutItem`, `UNNotificationResponse`) are never stored in a `NebulaLink`** — the Sendable bits (`url`/`identifier`/`title`/`payload`) are extracted at the adapter boundary, so the `NebulaLink` crosses any `@Sendable` `Task` closure cleanly. `payload` is a best-effort `[String: String]` coercion of `userInfo`/`ShortcutItem.userInfo`.

### 2. Resolve — `NebulaLinkParser<Route>` + `NebulaCompositeLinkParser`

`NebulaLinkParser<Route>: Sendable` is the **app-provided port** (primary associated type `Route: NebulaRoute`): a sync/pure `resolve(_ link: NebulaLink) -> NebulaLinkDestination<Route>`. Sync for v1 (URL parsing is synchronous). A future **async** path (a parser that needs a DB/API lookup) is added as a **default extension method** `resolveAsync`, NOT a new requirement — adding a requirement would break conformers and the `any NebulaLinkParser<Route>` existential; a default extension method is additive and non-breaking.

`NebulaLinkDestination<Route>` is the 5-case enum:

| Case | Meaning |
| --- | --- |
| `.unhandled` | the parser did not recognize the link — no-op (named `.unhandled`, NOT `.none`, to avoid an `Optional.none` clash in pattern matching) |
| `.present(Route)` | present a single route, dispatched by its `presentationStyle` |
| `.pushStack([Route])` | rebuild the push path (the deep-link primitive) |
| `.pushStackAndPresent([Route], Route)` | rebuild the path, then present a route over it |
| `.dismiss` | dismiss the active modal |

`NebulaCompositeLinkParser<Route>: NebulaLinkParser<Route>, Sendable` holds `[any NebulaLinkParser<Route>]` and returns the **first non-`.unhandled`** result — lets the app register scheme/domain/source-specific parsers (one for `nebula://`, one for `https://myapp.com`, one for shortcuts, …) and compose them.

### 3. Apply — `NebulaLinkRouter<Router>` + the additive `apply(_:)` default extension

`NebulaLinkRouter<Router: NebulaPresentationRouter & Sendable>: Sendable` is the **one-line glue**: `open(_ link: NebulaLink) async { await router.apply(parser.resolve(link)) }`. The parser is held **existentially** (`let parser: any NebulaLinkParser<Router.Route>`) — runtime-swappable, composable via `NebulaCompositeLinkParser`. One generic param.

`NebulaPresentationRouter.apply(_ destination: NebulaLinkDestination<Route>) async` is an **additive default extension method, NOT a protocol requirement** — so `NebulaSpyRouter`, the Meridian `Router`, and any app router inherit it for free, with zero conformance burden and no breaking change. It is the single source of truth for "destination → router intents":

| Destination | Router intents |
| --- | --- |
| `.unhandled` | (none) |
| `.present(route)` | `present(route)` |
| `.pushStack(routes)` | `dismiss()` → `replaceStack(with: routes)` |
| `.pushStackAndPresent(routes, modal)` | `dismiss()` → `replaceStack(with: routes)` → `present(modal)` |
| `.dismiss` | `dismiss()` |

### Atomicity — why stack-rebuilds dismiss first

`NebulaPresentationRouter.replaceStack(with:)` does **not** touch the modal slot. So the two stack-rebuild destinations `dismiss()` first to clear any stale modal that may be open over the old stack — otherwise the rebuilt stack would surface under a dangling sheet/cover. The harmless `dismiss()` pop-when-no-modal is erased by the immediately-following `replaceStack`. `.present` and `.dismiss` are additive over the current state and do **not** dismiss-first.

The spy records the component intents (e.g. `.pushStack([.root, .detail])` → `[.dismiss, .replaceStack([.root, .detail])]`), so the atomicity is observable/testable.

## SwiftUI-native vs app-constructed (the Meridian boundary)

The owner's decision (via AskUserQuestion): **SwiftUI-native entry-point adapters in Meridian; the rest app-constructed.** This keeps Meridian UIKit-free and the library valid on all 5 platforms.

### SwiftUI-native in Meridian — `.meridianDeepLinks` + `.meridianUserActivity`

- `.meridianDeepLinks(_ linkRouter:)` wires `.onOpenURL` — covers **deep links** (`myapp://`) and **universal links** (`https://`); both arrive via `.onOpenURL`, and `NebulaLink.init(url:)` infers the source by scheme. `URL` is `Sendable`, so the `Task { await linkRouter.open(NebulaLink(url: url)) }` capture is clean.
- `.meridianUserActivity(_ activityType:, _ linkRouter:)` wires `.onContinueUserActivity` — covers **Spotlight / Handoff / Siri**. `NSUserActivity` is **not Sendable** → the adapter builds the `NebulaLink` (extracting `activityType`/`title`/`webpageURL`/`userInfo → [String: String]`) **inside** the perform closure, before the `Task`, and captures only the `Sendable` link across the `@Sendable` `Task` boundary (no `#SendingClosureRisksDataRace`).

Both `ViewModifier`s are generic over `<R: NebulaPresentationRouter & Sendable>`. `.onOpenURL`/`.onContinueUserActivity` are available iOS 14/macOS 11/tvOS 14/watchOS 7 (visionOS via `*`) in the Xcode 27 SwiftUI `.swiftinterface` → no `@available`/`#if os()` gates at Meridian's `.v26` floor.

### App-constructed — shortcuts + notifications

Shortcuts (`UIApplicationShortcutItem`, UIKit) and notifications (`UNNotificationResponse`, UserNotifications) have **no SwiftUI View modifier** and/or pull UIKit → the app builds a `NebulaLink` in its delegate and calls `linkRouter.open(_:)`:

```swift
// Shortcut — UIApplicationDelegate.windowScene(_:performActionFor:completionHandler:)
let link = NebulaLink(source: .shortcut, identifier: shortcut.type, title: shortcut.localizedTitle,
    payload: shortcut.userInfo?.reduce(into: [String: String]()) { $0[String(describing: $1.key)] = String(describing: $1.value) } ?? [:])
Task { await linkRouter.open(link) }

// Notification — UNUserNotificationCenterDelegate.didReceive(_:with:)
let link = NebulaLink(source: .notification, identifier: response.actionIdentifier, title: content.title,
    payload: content.userInfo.reduce(into: [String: String]()) { $0[String(describing: $1.key)] = String(describing: $1.value) })
Task { await linkRouter.open(link) }
```

## Test doubles — `NebulaStubLinkParser` + `NebulaSpyLinkParser`

In `Sources/Nebula/Architecture/Testing/`, `public` in the product target (mirror `NebulaSpyRouter`):

- `NebulaStubLinkParser<Route>: NebulaLinkParser<Route>, Sendable` — `let destination`, returns it.
- `NebulaSpyLinkParser<Route>: NebulaLinkParser<Route>, Sendable` — `final class` + `let Mutex<[NebulaLink]>` → **derived** `Sendable` (no `@unchecked`); `callCount`/`links()`; defaults to `.unhandled`, overridable via `init(destination:)`.

## Binding invariants held

- **Nebula Foundation-only** — zero `import SwiftUI`/`UIKit` in `Sources/Nebula/` (grep-verified); all SwiftUI lives in Meridian. `dependencies: []` pristine.
- **Sendable, derived** — `NebulaLink`/`NebulaLinkDestination`/`NebulaLinkParser`/`NebulaCompositeLinkParser`/`NebulaLinkRouter`/`NebulaStubLinkParser` derive `Sendable`; `NebulaSpyLinkParser` = `final class` + `let Mutex` → derived `Sendable`. No `@unchecked` on any Nebula value type.
- **Additive, non-breaking** — the sole addition to `NebulaPresentationRouter` is a default extension method (not a requirement); `NebulaRoute`/`NebulaRouter`/`NebulaPresentation`/`NebulaSpyRouter`/Meridian `Router`/`MeridianNavigationStack` signatures unchanged. Async resolution is deferred as a default extension method (not a requirement).
- **5-platform, ungated** — the new Nebula types are Foundation-only; the Meridian modifiers are verified available below `.v26` → no gates.
- **`NSUserActivity` Sendable boundary** — the link is built inside the perform closure; only the Sendable link crosses the `Task`.

## Verification

- 1007 Nebula tests / 203 suites + 24 Meridian tests / 3 suites green (+22 Nebula / +4 Meridian over 0.18.0); zero concurrency warnings; release clean; all 5 platforms compile the new Nebula types ungated; Meridian modifiers ungated.
- Nebula `ArchitectureDeepLinkTests` (22 tests / 6 suites): `NebulaLink` source-inference + full init + Sendable/Equatable/Hashable; `NebulaLinkDestination` 5 cases; `NebulaLinkRouter` over `NebulaSpyRouter` + `NebulaStubLinkParser` asserting all 5 destination cases incl. `.pushStack` → `[.dismiss, .replaceStack([...])]` + the `apply(_:)`-inherited-by-spy case; `NebulaCompositeLinkParser` first-wins/all-unhandled/empty/Sendable; `NebulaStubLinkParser`/`NebulaSpyLinkParser` doubles.
- Meridian `DeepLinkTests` rewritten — `@MainActor` `NebulaLinkRouter` over the real `Router`, asserting `path`/`presented`/`presentedStyle` for all 5 cases incl. `pushStackClearsStaleModal`; the Wave III `sheet(item:)` Identifiable reference kept as a standalone `DestinationTests` suite.
- **CI as the strict-toolchain verifier** (per [[ci-macos26-runner-xcode265-stricter-than-local]]): the `NSUserActivity`-in-`Task` capture is the prime `#SendingClosureRisksDataRace` risk — the adapter is designed to build the `NebulaLink` **before** the `Task`.

## Deferred (tracked, not in N21)

- **Async link resolution** (`resolveAsync` default extension) — add when a parser needs a DB/API lookup.
- **Meridian first-class adapters for shortcuts/notifications** — deferred until a cross-platform-safe (non-UIKit) Meridian hook is justified; app-constructed `NebulaLink` covers them today.
- Tagging `0.19.0` deferred to the owner's gate decision.

## Related

- [[nebula-presentation-architecture]] — the model this conforms to (per-route style + modal slot + the async port).
- [[nebula-meridian-router]] — the SwiftUI sibling that supplies the adapters.
- [[nebula-presentation-destinations-deeplink]] — the superseded Wave III ad-hoc `URL → [Route]` (the example's `DeepLink.parse` is removed).
- [[adr-deep-links]] — the decision record.
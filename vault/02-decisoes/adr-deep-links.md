---
tags: [decisoes, adr, architecture, presentation, navigation, deeplink, universal-links, useractivity, swiftui, nebula]
aliases: [ADR deep links, ADR Wave N21, NebulaLink ADR, external navigation ADR]
related: [[nebula-deep-links]], [[nebula-presentation-architecture]], [[nebula-presentation-seams]], [[nebula-meridian-router]], [[nebula-presentation-destinations-deeplink]], [[nebula-clean-architecture-toolkit]]
status: accepted
date: "2026-07-22"
wave: "N21"
release: "Nebula 0.19.0"
---

# ADR — External navigation entries conforming to the router (Wave N21)

## Context

The only navigation entry wired into the router was **ad-hoc**: `MeridianExampleApp` hand-rolled a `DeepLink.parse(_ url: URL) -> [Route]` function hooked via SwiftUI's `.onOpenURL { url in Task { itemsRouter.replaceStack(with: DeepLink.parse(url)) } }` (Wave III). It was custom-scheme only (`nebula://`), lived entirely in the example app, had no Nebula abstraction, no test doubles, and no story for **universal links** (`https://`), **Spotlight/Handoff/Siri** `NSUserActivity`, **Home-screen shortcuts** (`UIApplicationShortcutItem`), or **notification taps** (`UNNotificationResponse`).

The owner asked that "every form of external navigation conform to the router" ("existem varias formas de navegar pelo app, precisamos enquadralas no nosso router … deeplinks, universal links, entre outras").

## Decision

Generalize the ad-hoc `URL → [Route]` into a Foundation-only **normalize → resolve → apply** pipeline (Nebula owns the model + port + glue; the SwiftUI entry-point adapters live in the Meridian sibling). Ships as **Nebula 0.19.0** (additive minor within Nebula 26); Meridian tracks. **Additive, non-breaking** — new public types + one additive **default extension method**; no protocol requirement changes.

1. **Normalize** — a `NebulaLink` (a `Sendable`/`Equatable`/`Hashable` value) normalizes any external event: a `Source` enum (`.urlScheme`/`.universalLink`/`.userActivity`/`.shortcut`/`.notification`/`.programmatic`) + `url`/`identifier`/`title`/`payload: [String: String]`. `init(url:)` infers `.universalLink` for `http`/`https` else `.urlScheme` (nil-scheme-safe). The non-Sendable Apple classes that originate these events are **never stored** in a `NebulaLink` — the Sendable bits are extracted at the adapter boundary.
2. **Resolve** — an app-provided `NebulaLinkParser<Route>: Sendable` port (primary associated type `Route`) turns the `NebulaLink` into a `NebulaLinkDestination<Route>` (`.unhandled`/`.present`/`.pushStack`/`.pushStackAndPresent`/`.dismiss` — `.unhandled` avoids an `Optional.none` clash). Sync/pure `resolve(_:)` for v1; async deferred as a **default extension method**, NOT a new requirement. `NebulaCompositeLinkParser<Route>` registers several parsers (first-non-`.unhandled`-wins).
3. **Apply** — a `NebulaLinkRouter<Router>` is the one-line glue: `open(_:)` → `await router.apply(parser.resolve(link))`. The destination→intents translation lives once in an additive **default extension method** `NebulaPresentationRouter.apply(_:)` (not a protocol requirement → `NebulaSpyRouter`/Meridian `Router` inherit it for free, zero conformance burden).

### Atomicity — dismiss-first for stack-rebuilds

`NebulaPresentationRouter.replaceStack(with:)` does **not** touch the modal slot. So `.pushStack`/`.pushStackAndPresent` `dismiss()` first to clear any stale modal that may be open over the old stack (otherwise the rebuilt stack surfaces under a dangling sheet/cover). The harmless `dismiss()` pop-when-no-modal is erased by the immediately-following `replaceStack`. `.present`/`.dismiss` are additive over the current state and do NOT dismiss-first.

### SwiftUI-native vs app-constructed split (owner decision, via AskUserQuestion)

- **SwiftUI-native in Meridian** — `.meridianDeepLinks(_:)` (`.onOpenURL` — covers deep links + universal links; `URL` is `Sendable` so the `Task` capture is clean) + `.meridianUserActivity(_:_:)` (`.onContinueUserActivity` — Spotlight/Handoff/Siri; `NSUserActivity` is **not Sendable** → the adapter builds the `NebulaLink` inside the perform closure, before the `Task`, capturing only the Sendable link across the `@Sendable` `Task` boundary — no `#SendingClosureRisksDataRace`).
- **App-constructed** — shortcuts (`UIApplicationShortcutItem`, UIKit) + notifications (`UNNotificationResponse`) have no SwiftUI View modifier and/or pull UIKit → the app builds a `NebulaLink` in its delegate and calls `linkRouter.open(_:)` (documented recipe — keeps Meridian UIKit-free and valid on all 5 platforms).

`.onOpenURL`/`.onContinueUserActivity` verified available iOS 14/macOS 11/tvOS 14/watchOS 7 (visionOS via `*`) in the Xcode 27 SwiftUI `.swiftinterface` → no `@available`/`#if os()` gates at Meridian's `.v26` floor.

## Consequences

- **One navigation seam for external + in-app** — deep links, universal links, Spotlight, shortcuts, notifications, and in-app buttons all conform to the same `NebulaPresentationRouter`.
- **Additive `apply(_:)` default extension, not a requirement** — `NebulaSpyRouter`/Meridian `Router`/any app router inherit it; zero conformance burden, no breaking change. The destination→intents translation lives once.
- **Nebula stays Foundation-only** — zero `import SwiftUI`/`UIKit` in `Sources/Nebula/` (grep-enforced); all SwiftUI lives in Meridian. `dependencies: []` pristine. `Sendable` derived throughout (no `@unchecked` on any Nebula value type); the spy parser mirrors `NebulaSpyRouter` (`final class` + `let Mutex<[NebulaLink]>` → derived `Sendable`).
- **`NSUserActivity` Sendable boundary** — the Meridian adapter extracts Sendable bits and builds the `NebulaLink` before the `Task`; only the Sendable link crosses the `@Sendable` `Task` closure.
- **Supersedes the ad-hoc Wave III `URL → [Route]`** — the example's `DeepLink.parse` is removed; `MeridianExampleApp` migrates to `AppLinkParser: NebulaLinkParser` + `NebulaLinkRouter` + `.meridianDeepLinks`/`.meridianUserActivity`, with an in-app `@Environment(\.openURL)` button to exercise the path.
- **Test counts** — 22 Nebula tests (`ArchitectureDeepLinkTests` / 6 suites) + 4 Meridian tests (`DeepLinkTests` rewritten — `NebulaLinkRouter` over the real `Router`, all 5 destination cases incl. stack-rebuild-clears-stale-modal); the Wave III `sheet(item:)` Identifiable reference kept as a standalone suite. 1007 Nebula tests / 203 suites + 24 Meridian tests / 3 suites green; zero concurrency warnings; release clean; all 5 platforms compile the new Nebula types ungated; Meridian modifiers ungated.

## Deferred (tracked, not in N21)

- **Async link resolution** (`resolveAsync` default extension) — add when a parser needs a DB/API lookup.
- **Meridian first-class adapters for shortcuts/notifications** — deferred until a cross-platform-safe (non-UIKit) Meridian hook is justified; app-constructed `NebulaLink` covers them today.
- Tagging `0.19.0` deferred to the owner's gate decision.

## Alternatives considered

- **A breaking full-state setter on the router** (e.g. `setState(path:modal:)`) — rejected: would not be additive and would force every conformer to implement it. The 5-case destination enum + the additive `apply(_:)` default extension achieves the compound "rebuild + modal" case (`.pushStackAndPresent`) without any protocol change.
- **`.unhandled` as `Optional.none`** — rejected: the parser's `resolve` returns a non-optional `NebulaLinkDestination`, and naming the no-op case `.none` would clash with `Optional.none` in pattern matching. `.unhandled` is unambiguous.
- **A generic `NebulaLinkRouter<Router, Parser: NebulaLinkParser>` (two type params)** — rejected for the primary form: the parser is runtime-swappable and composed existentially (`NebulaCompositeLinkParser` holds `[any NebulaLinkParser<Route>]`), so the existential `any NebulaLinkParser<Router.Route>` form (one generic param) is the better fit. Sync `resolve` keeps the existential cheap.
- **Shortcuts/notifications as Meridian adapters** — rejected (owner decision): they pull UIKit (`UIApplicationShortcutItem`) and/or have no SwiftUI View modifier, which would either gate Meridian off tvOS/watchOS/visionOS or force a UIKit import. App-constructed `NebulaLink`s keep Meridian UIKit-free and the library valid on all 5 platforms.
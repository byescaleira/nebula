# External Navigation Entries

The Foundation-only seam that funnels **every** external navigation entry — deep links, universal links, Spotlight/Handoff/Siri, Home-screen shortcuts, notification taps, and in-app "go here" — through one normalized value, one app-provided parser port, and one router glue, so they all conform to the same ``NebulaPresentationRouter``.

## Overview

Before this layer, the only navigation entry wired into the router was ad-hoc: a hand-rolled `URL → [Route]` function hooked via SwiftUI's `.onOpenURL`. It was custom-scheme only, lived in the app, had no abstraction, no test doubles, and no story for universal links, `NSUserActivity`, shortcuts, or notifications.

Wave N21 generalizes it into a Foundation-only pipeline (Nebula owns the model + the port + the glue; the SwiftUI entry-point adapters live in the Meridian sibling):

1. **Normalize** — whatever the source, build a ``NebulaLink`` (a `Sendable`/`Equatable`/`Hashable` value). ``NebulaLink/init(url:)`` infers the source from the scheme (`.universalLink` for `http`/`https`, else `.urlScheme`); the full init carries an explicit ``NebulaLink/Source``, an `identifier`, a `title`, and a `payload`.
2. **Resolve** — an app-provided ``NebulaLinkParser`` port turns the ``NebulaLink`` into a ``NebulaLinkDestination`` (`.unhandled` / `.present` / `.pushStack` / `.pushStackAndPresent` / `.dismiss`). A ``NebulaCompositeLinkParser`` registers several parsers and returns the first non-`.unhandled` result.
3. **Apply** — a ``NebulaLinkRouter`` is the one-line glue: `open(_:)` resolves the link and `await`s ``NebulaPresentationRouter/apply(_:)``, the additive **default extension method** that translates the destination into router intents.

The `apply(_:)` translation is a **default extension method, not a protocol requirement** — so ``NebulaSpyRouter`` and the Meridian `Router` inherit it for free, with zero conformance burden and no breaking change. It is the single source of truth for "destination → router intents".

### The six sources

``NebulaLink/Source`` enumerates where a navigation request can originate:

- `.urlScheme` — a custom-scheme deep link (`myapp://item/1`).
- `.universalLink` — an `http`/`https` universal link (`https://myapp.com/item/1`). ``NebulaLink/init(url:)`` infers this from the scheme.
- `.userActivity` — Spotlight, Handoff, or Siri `NSUserActivity`.
- `.shortcut` — a Home-screen quick action (`UIApplicationShortcutItem`).
- `.notification` — a push/local notification tap (`UNNotificationResponse`).
- `.programmatic` — an in-app "go here" reusing the same parser/router path.

The non-Sendable Apple classes that originate these events (`NSUserActivity`, `UIApplicationShortcutItem`, `UNNotificationResponse`) are **never stored** in a ``NebulaLink`` — the Sendable bits (`url`/`identifier`/`title`/`payload`) are extracted at the adapter boundary, so the ``NebulaLink`` crosses any `@Sendable` `Task` closure cleanly.

### SwiftUI-native vs app-constructed (Meridian stays UIKit-free)

Meridian supplies the SwiftUI-native entry-point adapters:

- `.meridianDeepLinks(_:)` wires `.onOpenURL` — covers **deep links** and **universal links** (both arrive via `.onOpenURL`; ``NebulaLink/init(url:)`` infers the source). `URL` is `Sendable`, so the `Task` capture is clean.
- `.meridianUserActivity(_:_:)` wires `.onContinueUserActivity` — covers **Spotlight / Handoff / Siri**. `NSUserActivity` is **not Sendable**, so the adapter builds the ``NebulaLink`` (extracting `activityType`/`title`/`webpageURL`/`userInfo → [String: String]`) **inside** the perform closure, before the `Task`, and captures only the `Sendable` link across the `@Sendable` `Task` boundary (no `#SendingClosureRisksDataRace`).

Shortcuts (`UIApplicationShortcutItem`) and notifications (`UNNotificationResponse`) have **no SwiftUI View modifier** and/or pull UIKit → the app builds a ``NebulaLink`` in its delegate and calls `linkRouter.open(_:)` directly:

```swift
// Shortcut (UIApplicationDelegate.windowScene(_:performActionFor:completionHandler:))
let link = NebulaLink(
    source: .shortcut,
    identifier: shortcut.type,
    title: shortcut.localizedTitle,
    payload: shortcut.userInfo?.reduce(into: [String: String]()) { $0[String(describing: $1.key)] = String(describing: $1.value) } ?? [:]
)
Task { await linkRouter.open(link) }

// Notification (UNUserNotificationCenterDelegate.didReceive:)
let link = NebulaLink(
    source: .notification,
    identifier: response.actionIdentifier,
    title: response.notification.request.content.title,
    payload: response.notification.request.content.userInfo.reduce(into: [String: String]()) { $0[String(describing: $1.key)] = String(describing: $1.value) }
)
Task { await linkRouter.open(link) }
```

This keeps Meridian UIKit-free and valid on all 5 platforms.

### Atomicity — dismiss-first for stack-rebuilds

``NebulaPresentationRouter/replaceStack(with:)`` does **not** touch the modal slot. So the two stack-rebuild destinations must `dismiss()` first to clear any stale modal that may be open over the old stack — otherwise the rebuilt stack would surface under a dangling sheet/cover. The harmless `dismiss()` pop-when-no-modal is erased by the immediately-following `replaceStack`. ``NebulaPresentationRouter/apply(_:)`` encodes this once:

| Destination | Router intents |
| --- | --- |
| `.unhandled` | (none) |
| `.present(route)` | `present(route)` |
| `.pushStack(routes)` | `dismiss()` → `replaceStack(with: routes)` |
| `.pushStackAndPresent(routes, modal)` | `dismiss()` → `replaceStack(with: routes)` → `present(modal)` |
| `.dismiss` | `dismiss()` |

`.present` and `.dismiss` are additive over the current state and do **not** dismiss-first.

### Why the port is sync (for now)

``NebulaLinkParser/resolve(_:)`` is synchronous and pure for v1 — URL parsing is synchronous. A future **async** resolution path (e.g. a parser that needs a DB/API lookup) is added as a **default extension method** (`resolveAsync`), **not** a new protocol requirement — adding a requirement would break conformers and the `any NebulaLinkParser<Route>` existential; a default extension method is additive and non-breaking.

## Topics

### The normalized link
- ``NebulaLink``
- ``NebulaLink/Source``
- ``NebulaLink/init(url:)``
- ``NebulaLink/init(source:url:identifier:title:payload:)``

### The resolved destination
- ``NebulaLinkDestination``

### The parser port + composite
- ``NebulaLinkParser``
- ``NebulaCompositeLinkParser``

### The glue + the apply extension
- ``NebulaLinkRouter``
- ``NebulaPresentationRouter/apply(_:)``

### Test doubles
- ``NebulaStubLinkParser``
- ``NebulaSpyLinkParser``
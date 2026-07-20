---
tags: [padroes, architecture, errors, user-error, clean-architecture, nebula]
aliases: [NebulaUserError, RecoveryAction, withUserMessageMap, nebula-user-error, user-error bridge]
related: [[nebula-errors]], [[nebula-domain-error]], [[nebula-error-taxonomy-toolkit]], [[nebula-clean-architecture-toolkit]], [[nebula-usererror-environment-featureflags]]
status: shipped
shipped: "0.9.0 (Wave N12, 2026-07-20)"
---

# Nebula User-Error Bridge

The architecture-toolkit user-facing error surface (Wave N12 / 0.9.0): a Foundation-tier **value** (`NebulaUserError`) the presentation layer renders, produced by a **configuration-layer map** from the closed `NebulaError` envelope — `NebulaError → NebulaUserError?`. **Mapping only — no new `NebulaError.Kind` cases.** The deeper research (verdict table, HIG tone, Apple `LocalizedError`/`RecoverableError` analysis, `RecoveryURL` refutation) lives in [[nebula-usererror-environment-featureflags]] (the bundled note covers user-error + environment + feature-flags; this note is the user-error dimension split out as shipped). Source of truth = root docs (`ARCHITECTURE.md`, `DECISIONS.md`); on conflict, the root doc wins. Part of [[nebula-clean-architecture-toolkit]].

## The gap

Apple's error model is two-layer: a *developer-facing* `Error`/`NSError` + a *user-facing* surface via `LocalizedError` (four optional strings) + `RecoverableError` (closure-based option list + `attemptRecovery` callbacks). **There is no Apple "user-error value type"** — `LocalizedError` IS the port, and *presentation* (alert/sheet/button copy) is UI-tier (AppKit `presentError` / UIKit `UIAlertController` / SwiftUI alert), never Foundation. `NebulaError` already conforms to `LocalizedError` + `CustomNSError` and populates `errorUserInfo` (`NebulaError.swift:178-188`), but `NebulaError.message` is developer-facing English — there is no Foundation-tier value an app/Cosmos can render as a user-facing error with recovery actions. N12 fills that gap.

## The value, not a layer error — opposite direction

`NebulaUserError` is a `Sendable`, `Equatable`, `Hashable` struct (`message: String`, `recoveryActions: [RecoveryAction]`, `helpAnchor: String?`). It is **NOT a `NebulaFailure`** — it is the *opposite* direction. `NebulaFailure` (see [[nebula-domain-error]]) bridges a layer error **into** the closed `NebulaError.Kind` envelope (`toNebulaError(kind:)`); `NebulaUserError` is the **output** of a map **out of** that envelope. So it has no `coarseKind`, no `toNebulaError`, and **no** coupling to the closed `Kind` enum. Adding user-facing errors never adds a `Kind` case. This distinction is the load-bearing design decision — see [[#Why not a NebulaFailure]] below.

## `RecoveryAction` is Nebula-authored

Apple's `RecoverableError` is **closure-based** (`attemptRecovery(optionIndex:)` callbacks) — it bakes UI and timing into the error value. There is no `RecoveryAction` enum in Apple, so Nebula authors one: a value enum (`.retry` / `.cancel` / `.dismiss` / `.custom(String)`) that carries the recoverable intent as **data**, leaving the presentation layer free to surface it. `RecoveryAction` conforms to `Sendable`, `Equatable`, `Hashable`, `CustomStringConvertible` (the `description` is a ready verb button title — "Retry"/"Cancel"/"Dismiss"/custom label — for the default/English path; HIG: button titles are verbs). The app localizes by switching on the case (not by reading `description`), so `description` is the developer fallback only.

## The configuration-layer map

`NebulaErrorConfiguration.withUserMessageMap(_:)` installs a `@Sendable` map keyed by `(NebulaError.Kind, [String: String]) → NebulaUserError?`. The dictionary is `NebulaError.metadata` — runtime context an app can interpolate into a message. The map returns `NebulaUserError?` so a custom map can decline to surface a kind (`nil`). The default map is `{ _, _ in nil }` (opt-in — no user-facing value unless configured).

```swift
let config = NebulaErrorConfiguration.default
    .withUserMessageMap { kind, context in
        NebulaUserError.default(for: kind, context: context)
    }
if let user = config.userError(for: error) { /* app/Cosmos renders user */ }
```

### The default English table

`NebulaUserError.default(for:context:)` ships an English fallback per `Kind` with HIG-neutral tone (non-accusatory, no "you/your/we") and sensible recovery actions:

| Kind | Message | Recovery actions |
|---|---|---|
| `.network` | "Unable to reach the service." | `[.retry, .cancel]` |
| `.decoding` / `.serialization` / `.encoding` | "Couldn't read the received data." | `[.dismiss]` |
| `.cocoa` | "The operation couldn't be completed." | `[.retry, .cancel]` |
| `.file` | "Couldn't access the file." | `[.retry, .cancel]` |
| `.validation` | "Please review the highlighted fields." | `[.dismiss]` |
| `.unknown` | "Something went wrong." | `[.dismiss]` |

The app overrides the map for **L10n** via `String(localized:)` **at the app layer** — Nebula emits developer-facing English only (no `String(localized:)` / `NSLocalizedString` in `Sources/`). `context` is accepted for signature parity with custom maps; the default uses fixed strings.

## Orthogonal to reporting

`NebulaErrorConfiguration.userError(for:)` is **NOT** gated on `isEnabled` — user-message mapping is orthogonal to reporting. An app surfaces a user-facing value whether or not errors are reported. The process-wide convenience is `NebulaErrorConfig.userError(for:)` (mirrors `NebulaErrorConfig.report(_:)`); the explicit-parameter path passes a `NebulaErrorConfiguration` directly (the testable path — never resolve from the accessor in a test; isolate accessor tests with `@Suite(.serialized)`).

## Sendable / Equatable posture

- `NebulaUserError` / `RecoveryAction`: derive `Sendable` (pure values, no `@unchecked`); `Equatable` + `Hashable` (supports test assertions).
- The map closure is `@Sendable` (crosses isolation).
- `NebulaErrorConfiguration` stays `Sendable`-NOT-`Equatable` — the existing `handler` closure already disqualifies `Equatable`; a second `@Sendable` closure changes nothing. Mirrors `CosmosErrorConfiguration`.
- `NebulaErrorEvent` is **unchanged** — the bridge is a separate accessor, not part of the reporting event.

## Why not a `NebulaFailure`

`NebulaFailure.toNebulaError(kind:)` is the **layer → envelope** bridge (a domain/validation/repository error becomes a `NebulaError`). `NebulaUserError` is the **envelope → user value** bridge — the opposite direction. Conflating them would force `NebulaUserError` to carry a `coarseKind` and a `toNebulaError`, coupling a user-facing value back to the closed `Kind` enum it's meant to abstract over. Keeping them separate preserves the directional purity: layer errors flow inward to the envelope; the user value flows outward from the envelope. The map is on the **configuration**, not on the failure type — so the user-error concern is opt-in and app-supplied, never a library default that emits UI strings.

## What's deferred

- **`NebulaError` adopting `RecoverableError`** — closure-based, bakes UI/timing into the error value; opt-in conformance is an app/Cosmos decision; closures crossing isolation need `@Sendable` handlers.
- **`NebulaErrorPresenter` port** — Cosmos-only. Presentation (alert/sheet/button copy) is UI; Nebula doesn't own UI. Cosmos is the SwiftUI sibling that renders.
- **`RecoveryURL`** — NOT public Apple API (only the private `_PKErrorRecoveryURLKey` in `PassKit.tbd`/`FinanceKit.tbd`). Refuted — would be inventing a non-Apple surface. The public primitives are `RecoverableError` + `recovery_attempterErrorKey`.

The other two dimensions in [[nebula-usererror-environment-featureflags]] are **not** N12: environment → N13, feature flags → N14 (both still `researched`).

## Sources

- Apple HIG — Alerts — https://developer.apple.com/design/human-interface-guidelines/alerts
- Apple HIG — Writing — https://developer.apple.com/design/human-interface-guidelines/writing
- WWDC17 813 "Writing Great Alerts" — https://developer.apple.com/videos/play/wwdc2017/813/
- WWDC24 10140 "Add personality to your app through UX writing" — https://developer.apple.com/videos/play/wwdc2024/10140/
- SE-0112 "Improved NSError Bridging" — https://github.com/swiftlang/swift-evolution/blob/main/proposals/0112-nserror-bridging.md
- NSHipster — LocalizedError/RecoverableError/CustomNSError — https://nshipster.com/swift-foundation-error-protocols/

## UNVERIFIED caveats (from the bundled research)

- `RecoveryURL` "AppKit/macOS only" premise — refuted as non-existent (no public API); the "AppKit-only" framing is UNVERIFIED — do not cite as fact.
- Any "WWDC Foundation errors" specific session citation — error protocols come from SE-0112 (Swift 3, 2016), not a WWDC talk; UNVERIFIED — do not cite as fact.
- `presentError` (AppKit) line number — UNVERIFIED (grep zero hits in `AppKit.swiftinterface`); the API is UI-tier regardless, doesn't affect any Nebula verdict.
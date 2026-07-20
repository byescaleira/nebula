---
tags: [padroes, architecture, environment, configuration, foundation, nebula]
aliases: [NebulaEnvironment, NebulaEnvironmentConfiguration, NebulaEnvironmentConfig, fromBundle, nebula-environment, environment reader]
related: [[nebula-usererror-environment-featureflags]], [[nebula-standardize-measure]], [[nebula-preferences]], [[nebula-clean-architecture-toolkit]]
status: shipped
shipped: "0.10.0 (Wave N13, 2026-07-20)"
---

# Nebula Environment Value + Reader

The architecture-toolkit environment surface (Wave N13 / 0.10.0): a closed `NebulaEnvironment` enum that round-trips the app's `Info.plist` configuration string, a `fromBundle(_:key:)` reader, and an `NebulaEnvironmentConfiguration` value carrying per-environment base URLs + string overrides. **Value + reader only — the `.xcconfig`/scheme/`Info.plist` wiring is app-tier and deferred.** The deeper research (Sendability table, `Bundle`/`ProcessInfo`/`UserDefaults` verification, `ProcessInfo` alternative) lives in [[nebula-usererror-environment-featureflags]] (the bundled note covers user-error + environment + feature-flags; this note is the environment dimension split out as shipped). Source of truth = root docs (`ARCHITECTURE.md`, `DECISIONS.md`); on conflict, the root doc wins. Part of [[nebula-clean-architecture-toolkit]].

## The gap

**There is no Apple-native "environment" API** — verified by zero `struct/enum/class Environment` hits in `Foundation.swiftmodule`. Apple's pattern is pure build-config convention: `.xcconfig` → `$(CONFIGURATION)` substitution into an `Info.plist` key → runtime read via `Bundle.main.object(forInfoDictionaryKey:)`, with `#if DEBUG` and per-scheme build configurations. That wiring is **app-target work**; a library can only contribute a typed value + a reading pattern. N13 ships exactly that.

## `NebulaEnvironment` — closed enum

`NebulaEnvironment` is a `String`-backed enum (`.development` / `.staging` / `.production`) conforming to `Sendable`, `Equatable`, `Hashable`, `CaseIterable`, `CustomStringConvertible` — all **derived** (pure value, no `@unchecked`). The raw value round-trips the `Info.plist` string. `static let default = .production` — an app that never wires the key resolves to the **safest posture** (never accidentally talk to a dev URL).

## `fromBundle(_:key:)` — the reader

The first `Bundle`-reading code in Nebula. Reads `object(forInfoDictionaryKey:)` (default key `"Configuration"`, the `$(CONFIGURATION)` idiom; default `bundle .main`), casts `Any? → String?`, and maps through `init(rawValue:)`.

```swift
let env = NebulaEnvironment.fromBundle()
let config = NebulaEnvironmentConfiguration.default
    .withEnvironment(env)
    .withBaseURLs([.production: URL(string: "https://api.acme.com")!])
let baseURL = config.baseURL(for: env)
```

### Safe-fail-to-production

Absent key, unknown string, or non-`String` value → `.default` (`.production`). The function never returns `nil` — an app always has *an* environment.

### The `Any → String` Sendability step

`Bundle` is `@unchecked Sendable` (Sendable on the `.v26` floor), and `object(forInfoDictionaryKey:)` returns `Any?`. The `infoDictionary` values are `Any` and are **not** Sendable, so the reader casts `Any? → String?` *before* it is stored or returned — an un-cast `Any` never crosses an isolation boundary. The reader is a **pure function** over the Sendable `Bundle`; no shared mutable state, so **no `Mutex` is needed** (unlike `NebulaDefaults` over the non-Sendable `UserDefaults`).

## `NebulaEnvironmentConfiguration` — the value

The fifth of Nebula's cross-cutting configuration contracts (alongside `NebulaLogConfiguration` / `NebulaErrorConfiguration` / `NebulaStandards` / `NebulaMeasureConfiguration`). A `Sendable`-only struct (NOT `Equatable` — family posture; it carries no `@Sendable` handler, but keeps the posture for consistency). Fields: `environment: NebulaEnvironment`, `baseURLs: [NebulaEnvironment: URL]`, `overrides: [String: String]` — all `let`, all derive `Sendable`, no `@unchecked`.

`.with*` builders return the **concrete type** (not `Self`), reconstruct via `.init(...)` forwarding unchanged fields (mirrors `NebulaStandards.withLocale`). `baseURL(for:)` returns `nil` for an unregistered environment — **Nebula ships no built-in URLs** (the app supplies all). `value(for:)` is the override accessor. `static let default` is the once-token (no separate `bootstrap()`).

## Naming — `Configuration` / `Config` split

The value struct is `NebulaEnvironmentConfiguration` and the process-wide accessor is `NebulaEnvironmentConfig`, mirroring the four-family convention (`NebulaLogConfiguration`/`NebulaLogConfig`, `NebulaErrorConfiguration`/`NebulaErrorConfig`, `NebulaMeasureConfiguration`/`NebulaMeasureConfig`; `NebulaStandards`/`NebulaStandardsConfig` is the lone exception where the value drops the `Configuration` suffix). This split avoids the `NebulaEnvironmentConfigConfig` stutter.

## Two-path DI

`NebulaEnvironmentConfig` holds the current config in a `Mutex<NebulaEnvironmentConfiguration>` (`Synchronization`; below the `.v26` floor, no `@available` gate). `get()` / `set(_:)` are the ergonomic path; passing an explicit `NebulaEnvironmentConfiguration` parameter is the testable path (DECISIONS.md row 27 — the two-path rule). `Mutex` is `~Copyable` / `@_staticExclusiveOnly` → the backing `static let current` is a `let`, never `var`. No convenience methods (the config exposes no `@Sendable` handler to forward — `baseURL(for:)` / `value(for:)` are pure and called on `get()` directly).

## What's deferred

- **`.xcconfig`/scheme/`Info.plist` wiring** — app-tier (the consuming app's Xcode project writes `$(CONFIGURATION)` into the `Configuration` key). Nebula ships the reader, not the project setup.
- **`ProcessInfo.processInfo.environment`-based reader** — a documented alternative in [[nebula-usererror-environment-featureflags]] (L43); **not shipped** — the `Info.plist`-keyed reader is the only one Nebula provides. `ProcessInfo` is Sendable, so a future reader would be straightforward, but N13 ships one path.
- **Reader façade / interpolator** — skipped. `Bundle` is Sendable and a pure value builder suffices; the app reads `NebulaEnvironmentConfiguration` directly (house idiom: prefer value types over a `final class` when a value works).

Feature flags (the third dimension in [[nebula-usererror-environment-featureflags]]) are **not** N13 — N14 (still `researched`).

## Sources

- `Foundation.swiftmodule/arm64e-apple-ios.swiftinterface` (Xcode 27 Beta 3) — zero `struct/enum/class Environment` hits; `Bundle` Sendable (compile-verified).
- NSHipster — Xcode Build Configuration Files — https://nshipster.com/xcconfig/
- Apple Developer — Build settings reference (`CONFIGURATION`) — https://developer.apple.com/documentation/xcode/build-settings-reference

## UNVERIFIED caveats (from the bundled research)

- `presentError` (AppKit) line number — UNVERIFIED (grep zero hits in `AppKit.swiftinterface`); UI-tier regardless, doesn't affect any Nebula verdict.
- Any `ProcessInfo`-based reader beyond the `Info.plist` key is documented but **not shipped** — treat as a future option, not a current contract.
# Environment

A closed `NebulaEnvironment` enum that round-trips the app's `Info.plist` configuration string, plus a `fromBundle(_:key:)` reader and an `NebulaEnvironmentConfiguration` value carrying per-environment base URLs and string overrides.

## Overview

Apple provides no Foundation `Environment` value type. The idiom is the Xcode `Configuration` build setting (`Debug`/`Release`/custom), fed from `.xcconfig` + schemes and written into the app's `Info.plist` under a key — conventionally `Configuration`, set from `$(CONFIGURATION)`. Nebula ships the **value + reader**: ``NebulaEnvironment`` is a closed `String`-backed enum that round-trips that string, and ``NebulaEnvironment/fromBundle(_:key:)`` reads the key from a bundle's `Info.plist` and resolves it.

```swift
let env = NebulaEnvironment.fromBundle()   // reads Bundle.main Info.plist "Configuration"
let config = NebulaEnvironmentConfiguration.default
    .withEnvironment(env)
    .withBaseURLs([
        .development: URL(string: "https://dev.acme.com")!,
        .staging:     URL(string: "https://stg.acme.com")!,
        .production:  URL(string: "https://api.acme.com")!
    ])

let baseURL = config.baseURL(for: env)     // nil if the app never registered it
```

### Safe-fail-to-production

``NebulaEnvironment/default`` is ``production``. An app that never wires the `Configuration` key resolves to the safest posture rather than accidentally talking to a development or staging service. ``NebulaEnvironment/fromBundle(_:key:)`` returns ``default`` when the key is absent, the string is unknown, or the value is not a `String` — it never returns `nil`, because an app always has *an* environment.

### The `Any → String` Sendability step

`Bundle` is `@unchecked Sendable` (Sendable on the `.v26` floor), and `object(forInfoDictionaryKey:)` returns `Any?`. The `infoDictionary` values are `Any` and are **not** Sendable, so the reader casts `Any?` to `String?` *before* it is stored or returned — an un-cast `Any` never crosses an isolation boundary. The reader is a pure function over the Sendable `Bundle`; there is no shared mutable state, so no `Mutex` is involved.

### App-tier wiring is deferred

Nebula ships the **reader**, not the Xcode project setup. The `.xcconfig`/scheme/`Info.plist` wiring is the consuming app's work (writing `$(CONFIGURATION)` into the `Configuration` key). A `ProcessInfo.processInfo.environment`-based reader is a documented alternative but is not shipped — the `Info.plist`-keyed reader is the only one Nebula provides.

### Builders and process-wide access

``NebulaEnvironmentConfiguration`` is the fifth of Nebula's cross-cutting configuration contracts (alongside ``NebulaLogConfiguration``, ``NebulaErrorConfiguration``, ``NebulaStandards``, and ``NebulaMeasureConfiguration``; see <doc:Standardize> for the sibling pattern). It carries no `@Sendable` handler (the environment is resolved data, not a fan-out path) and follows the family's `Sendable`-only posture. Override pieces with ``NebulaEnvironmentConfiguration/withEnvironment(_:)``, ``NebulaEnvironmentConfiguration/withBaseURLs(_:)``, and ``NebulaEnvironmentConfiguration/withOverrides(_:)``. Resolve URLs with ``NebulaEnvironmentConfiguration/baseURL(for:)`` (returns `nil` for an unregistered environment — Nebula ships no built-in URLs) and string overrides with ``NebulaEnvironmentConfiguration/value(for:)``. An app's composition root (see <doc:Architecture>) typically reads the environment once at launch and wires the per-environment base URLs into its gateways.

### Why a `Mutex`

`NebulaEnvironmentConfiguration` is a plain `Sendable` value; the **process-wide accessor** ``NebulaEnvironmentConfig`` holds the current config in a `Mutex<NebulaEnvironmentConfiguration>` from `Synchronization` (`Mutex` requires iOS 18 / macOS 15 / watchOS 11 / tvOS 18 / visionOS 2 — all below Nebula's `.v26` floor, so no `@available` gate). `get()` / `set(_:)` are the ergonomic path; passing an explicit ``NebulaEnvironmentConfiguration`` parameter is the testable path (the two-path DI rule, `DECISIONS.md`). `Mutex` is `~Copyable` and `@_staticExclusiveOnly`, so the backing property is a `let` (never `var`).

## Topics

### Value
- ``NebulaEnvironment``
- ``NebulaEnvironment/default``
- ``NebulaEnvironment/fromBundle(_:key:)``

### Configuration
- ``NebulaEnvironmentConfiguration``
- ``NebulaEnvironmentConfiguration/default``
- ``NebulaEnvironmentConfiguration/withEnvironment(_:)``
- ``NebulaEnvironmentConfiguration/withBaseURLs(_:)``
- ``NebulaEnvironmentConfiguration/withOverrides(_:)``
- ``NebulaEnvironmentConfiguration/baseURL(for:)``
- ``NebulaEnvironmentConfiguration/value(for:)``
- ``NebulaEnvironmentConfig``
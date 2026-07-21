# Feature flags

A `Sendable` feature-flag resolution port, an in-memory `Mutex`-backed façade, a remote-fetch port, and a priority-ordered composite — built on a `Sendable` value enum.

## Overview

There is no Apple-native remote-config or feature-flag API (zero `FeatureFlag` / `RemoteConfig` / `RolloutConfig` hits in `Foundation.swiftmodule`, Xcode 27 Beta 3), and `dependencies: []` forbids Firebase / LaunchDarkly, so a Nebula remote flag is necessarily a **port** the app conforms. Nebula ships the Foundation-tier pattern, not a backend:

- ``NebulaFlagValue`` — a `Sendable` value enum (`.bool` / `.string` / `.int` / `.double` / `.json(Data)`) that a flag carries;
- ``NebulaFeatureFlags`` — the resolution **port**, a `Sendable` protocol with one ``NebulaFeatureFlags/value(forKey:)`` requirement plus a default extension of typed accessors (`bool` / `string` / `int` / `double` / `number` / `json`) built on it — every conformer gets the ergonomics for free;
- ``NebulaLocalFeatureFlags`` — the concrete in-memory façade, a `final class` wrapping a `Mutex<[String: NebulaFlagValue]>` override map;
- ``NebulaRemoteFeatureFlags`` — a port refining ``NebulaFeatureFlags`` with a `refresh() async throws` requirement, served by an app-supplied backend;
- ``NebulaCompositeFeatureFlags`` — a `Sendable` struct resolving ``NebulaFeatureFlags/value(forKey:)`` by first-non-nil across an ordered source list.

The composite is a generic first-non-nil resolver — it does not hardcode local/remote/defaults. The app wires the priority conventionally as `[localOverrides, remote, builtInDefaults]`, so a local override shadows the remote fetch, and the remote shadows the built-in defaults:

```swift
let local = NebulaLocalFeatureFlags()
let remote = AcmeRemoteFeatureFlags()              // conforms NebulaRemoteFeatureFlags
let defaults = NebulaLocalFeatureFlags(["theme": .string("system")])
let flags = NebulaCompositeFeatureFlags([local, remote, defaults])

local.setValue(.string("dark"), forKey: "theme")
flags.string(forKey: "theme")   // "dark" — the local override wins
```

The seam model mirrors ``NebulaPreferences`` (the sibling port + façade): one low-level requirement plus typed default-extension bridges, so the ergonomics are shared across every conformer. Like the preferences façade, the local façade and the composite are **constructed-and-passed** — there is no process-wide `NebulaFeatureFlagsConfig` accessor (see <doc:ArchitectureCompositionRoot>). The composite conforms to ``NebulaFeatureFlags``, so the typed accessors flow through it for free.

### Why a `Mutex` and a `final class`

`[String: NebulaFlagValue]` is a `Sendable` value type, so — unlike ``NebulaDefaults`` (whose `UserDefaults` is `@_nonSendable(_assumed)` and needs a `sending` init) — ``NebulaLocalFeatureFlags`` wraps a plain value in a `Mutex` and the initializer takes it by value (no `sending`). `Mutex<T>` is `~Copyable` and `@_staticExclusiveOnly`, so a `Mutex`-typed stored property would propagate `~Copyable` to a *struct* owner; a `final class` absorbs the `~Copyable` `Mutex` behind a copyable, `Sendable` reference (region-based isolation, the alternative to `@unchecked` — derived, **no `@unchecked`**). The composite is a `struct`: its `[any NebulaFeatureFlags]` is `Sendable` (the protocol requires it), so the struct derives `Sendable` with no `Mutex` at all.

### What is deferred

`NebulaDefaults`-backed persistent overrides are **not** in this surface — the in-memory façade ships now, and persistence (which would adopt `Codable` on ``NebulaFlagValue``) is a follow-up. SwiftUI `@Environment` injection / an `@Observable` flag manager are Cosmos-only (Nebula has no SwiftUI). The remote backend itself is app-supplied. Rollout-percentage and audience targeting are backend-computed; Nebula evaluates locally on a fetched value.

## Topics

### Value
- ``NebulaFlagValue``

### Port
- ``NebulaFeatureFlags``
- ``NebulaFeatureFlags/value(forKey:)``
- ``NebulaFeatureFlags/bool(forKey:)``
- ``NebulaFeatureFlags/string(forKey:)``
- ``NebulaFeatureFlags/int(forKey:)``
- ``NebulaFeatureFlags/double(forKey:)``
- ``NebulaFeatureFlags/number(forKey:)``
- ``NebulaFeatureFlags/json(_:forKey:)``

### Concrete façade
- ``NebulaLocalFeatureFlags``

### Remote port
- ``NebulaRemoteFeatureFlags``
- ``NebulaRemoteFeatureFlags/refresh()``

### Composite
- ``NebulaCompositeFeatureFlags``
- ``NebulaCompositeFeatureFlags/withSource(_:)``
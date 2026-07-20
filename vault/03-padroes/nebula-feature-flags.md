---
tags: [padroes, architecture, feature-flags, foundation, nebula]
aliases: [NebulaFeatureFlags, NebulaFlagValue, NebulaLocalFeatureFlags, NebulaRemoteFeatureFlags, NebulaCompositeFeatureFlags, nebula-feature-flags, feature flags, feature flag port]
related: [[nebula-usererror-environment-featureflags]], [[nebula-preferences]], [[nebula-clean-architecture-toolkit]], [[nebula-app-readiness-research]]
status: shipped
shipped: "0.11.0 (Wave N14, 2026-07-20)"
---

# Nebula Feature Flags — Port + Façade + Remote Port + Composite

The architecture-toolkit feature-flag surface (Wave N14 / 0.11.0): a `Sendable` value enum, a one-requirement resolution port with typed default-extension bridges, an in-memory `Mutex`-backed façade, a remote-fetch port refining the base, and a priority-ordered first-non-nil composite. **There is no Apple-native remote-config or feature-flag API** (zero `FeatureFlag`/`RemoteConfig`/`RolloutConfig` hits in `Foundation.swiftmodule`, Xcode 27 Beta 3), and `dependencies: []` forbids Firebase/LaunchDarkly — so a remote flag is necessarily a **port** the app conforms. The deeper research (Sendability table, the `dependencies: []` rationale, the community pattern sources) lives in [[nebula-usererror-environment-featureflags]] (the bundled note covers user-error + environment + feature-flags; this note is the feature-flags dimension split out as shipped). Source of truth = root docs (`ARCHITECTURE.md`, `DECISIONS.md`); on conflict, the root doc wins. Part of [[nebula-clean-architecture-toolkit]].

## The gap

**No Apple-native remote-config/feature-flag API** — verified by zero `FeatureFlag`/`RemoteConfig`/`RolloutConfig` hits in `Foundation.swiftmodule`. Apple's only native primitive is `UserDefaults` (local) + `#if DEBUG`/`hasFeature()` (build-time). Remote flags require a backend the app supplies; `dependencies: []` forbids Firebase/LaunchDarkly, so a Nebula remote flag is a port the app conforms. N14 ships the Foundation-tier pattern — the value, the port, the in-memory façade, the remote port, and the composite — **not** a backend.

## `NebulaFlagValue` — the value

A `Sendable` value enum (the storage representation a flag carries), five payload kinds:

```swift
public enum NebulaFlagValue: Sendable, Equatable, Hashable, CustomStringConvertible {
    case bool(Bool)
    case string(String)
    case int(Int)
    case double(Double)
    case json(Data)
}
```

All associated values are `Sendable`/`Equatable`/`Hashable` → **derived**, no `@unchecked`. `.int` and `.double` are stored distinctly (no silent precision loss); the `number(forKey:)` accessor coerces either to `Double`. `CustomStringConvertible` for debugging. **`Codable` is not adopted yet** — it arrives with the `NebulaDefaults`-backed persistence follow-up (adding it later is additive).

## `NebulaFeatureFlags` — the port

The seam model mirrors [[nebula-preferences]]: **one low-level requirement + typed default-extension bridges**, so every conformer gets the ergonomics for free.

```swift
public protocol NebulaFeatureFlags: Sendable {
    func value(forKey key: String) -> NebulaFlagValue?   // the ONLY requirement
}
public extension NebulaFeatureFlags {
    func bool(forKey: String) -> Bool?          // .bool payload, else nil
    func string(forKey: String) -> String?       // .string payload, else nil
    func int(forKey: String) -> Int?            // .int payload (no coercion)
    func double(forKey: String) -> Double?       // .double payload (no coercion)
    func number(forKey: String) -> Double?       // .double OR .int → Double
    func json<T: Decodable>(_ type: T.Type, forKey: String) throws -> T?  // per-call JSONDecoder()
}
```

`value(forKey:)` is non-throwing (a lookup); only `json` throws (decoding can fail). Flag errors surface as `DecodingError` from the `json` bridge — **Nebula adds no new `NebulaError.Kind` case**. The `json` bridge constructs a `JSONDecoder` per call — `Sendable`, and deliberately decoupled from the gateway's `NebulaJSONDecoder` configuration (the `NebulaPreferences` rationale). The four research-named accessors (`bool`/`string`/`number`/`json`) are the primary surface; `int`/`double` are precision complements that return only their own case (no silent coercion — `int(forKey:)` does not return a `.double`).

## `NebulaLocalFeatureFlags` — the façade

Mirror [[nebula-preferences]]'s `NebulaDefaults`: a `final class` wrapping `Mutex<[String: NebulaFlagValue]>`. **Derived `Sendable`, no `@unchecked`**; the `final class` absorbs the `~Copyable` `Mutex` behind a copyable reference. The store is a `Sendable` value type, so — unlike `NebulaDefaults` (whose `UserDefaults` is `@_nonSendable(_assumed)` and needs a `sending` init) — the initializer takes the dict by value (**no `sending`**). Reference semantics is the right shape — an app shares one override store and mutates it at runtime.

```swift
let local = NebulaLocalFeatureFlags()
local.setValue(.bool(true), forKey: "new_dashboard")
local.bool(forKey: "new_dashboard")   // true
local.setValue(nil, forKey: "new_dashboard")   // nil → remove
```

## `NebulaRemoteFeatureFlags` — the remote port

Refines `NebulaFeatureFlags` with a `refresh()` requirement. A conformer serves the **last-fetched** flag values through `value(forKey:)` (the base-port requirement) and refreshes them on demand. The backend is app-supplied — `dependencies: []` forbids Firebase/LaunchDarkly.

```swift
public protocol NebulaRemoteFeatureFlags: NebulaFeatureFlags {
    func refresh() async throws   // re-fetch from the backend; failed refresh leaves cache unchanged
}
```

**`refresh() async throws`** deviates from the research's non-throwing `refresh() async` — a remote fetch failing is the whole point of local fallback; the composite never calls `refresh` (the app drives it at its own cadence), so `throws` is honest about fetch failure and costs the composite nothing.

## `NebulaCompositeFeatureFlags` — the composite

A `Sendable` **struct** holding an immutable `[any NebulaFeatureFlags]` and resolving `value(forKey:)` by **first-non-nil** across the sources in order. `Sendable` by derived conformance (`[any NebulaFeatureFlags]` where the protocol is `: Sendable`), **no `@unchecked`**, the shape mirroring `NebulaHTTPInterceptorChain`. `withSource(_:)` appends and returns a new composite (immutable after init). The composite is a **generic first-non-nil resolver** — it does not hardcode local/remote/defaults; the app wires the priority conventionally as `[localOverrides, remote, builtInDefaults]`:

```swift
let local = NebulaLocalFeatureFlags()
let remote = AcmeRemoteFeatureFlags()                       // conforms NebulaRemoteFeatureFlags
let defaults = NebulaLocalFeatureFlags(["theme": .string("system")])
let flags = NebulaCompositeFeatureFlags([local, remote, defaults])

local.setValue(.string("dark"), forKey: "theme")
flags.string(forKey: "theme")   // "dark" — the local override wins
```

Conforms to `NebulaFeatureFlags`, so the typed accessors (`bool`/`string`/`number`/`json`) flow through the composite for free.

## Why no process-wide accessor

Every `final class` store façade (`NebulaDefaults`/`NebulaKeychain`/`NebulaLocalFeatureFlags`) is **constructed-and-passed** — no `NebulaFeatureFlagsConfig` accessor (the `*Config` `Mutex` family is reserved for configuration **values**, Sendable structs). The composition root wires `[local, remote, defaults]` via explicit constructor injection (see [[nebula-composition-root]] — avoid hidden globals).

## What's deferred

- **`NebulaDefaults`-backed persistent overrides** — the research marks `NebulaDefaults` backing as *optional*; N14 ships the in-memory façade only, so the wave is self-contained with no N2 dependency. The follow-up would adopt `Codable` on `NebulaFlagValue` and bridge through `NebulaPreferences`.
- **SwiftUI `@Environment` injection / `@Observable` flag manager** — Cosmos-only (Nebula has no SwiftUI).
- **The remote backend itself** — app-supplied (`dependencies: []` forbids Firebase/LaunchDarkly).
- **Rollout-% / audience targeting** — backend-computed; Nebula evaluates locally on a fetched value.

## Sources

- `Foundation.swiftmodule/arm64e-apple-ios.swiftinterface` (Xcode 27 Beta 3) — zero `FeatureFlag`/`RemoteConfig`/`RolloutConfig` hits; `JSONDecoder`/`JSONEncoder` Sendable (compile-verified).
- Livsy Code — "A Feature Flags System in Swift" — https://livsycode.com/best-practices/a-feature-flags-system-in-swift/
- Statsig — "iOS feature flags: Swift patterns" — https://www.statsig.com/perspectives/ios-feature-flags-swift-patterns

## UNVERIFIED caveats (from the bundled research)

- The `NebulaFlagValue` case list (`.bool`/`.string`/`.int`/`.double`/`.json`) is a **design inference** from the four protocol accessors, not research-pinned (the bundled note names only "Sendable enum" + the four accessors). Adding a case later is additive.
- The research's `refresh() async` (non-throwing) was changed to `refresh() async throws` at ship — documented above.
---
tags: [padroes, architecture, preferences, userdefaults, concurrency, nebula]
aliases: [NebulaPreferences, NebulaDefaults, Nebula preferences port, UserDefaults façade]
related: [[nebula-data-network-architecture]], [[nebula-repository]], [[data-network-open-questions]], [[nebula-network-retry]]
status: shipped
shipped: "2026-07-19 (Wave N2)"
---

# Preferences — NebulaPreferences + NebulaDefaults (Wave N2 — shipped)

The UserDefaults half of the data+network surface ([[nebula-data-network-architecture]] Q6). A `Sendable` key-value **port** (`NebulaPreferences`) plus a concrete `Mutex`-wrapped `UserDefaults` **façade** (`NebulaDefaults`). Source of truth = `Sources/Nebula/Architecture/Preferences/NebulaPreferences.swift` + `NebulaDefaults.swift`; this note is synthesis.

## What shipped (Wave N2)

| Symbol | Path | Role |
|---|---|---|
| `NebulaPreferences` | `Architecture/Preferences/NebulaPreferences.swift` | The architecture seam — a `Sendable` protocol with three byte-level requirements: `data(forKey:)` / `setData(_:forKey:)` / `remove(forKey:)`. An app conforms it to swap the backing store (UserDefaults, iCloud key-value store, an encrypted store, a test double). |
| `NebulaPreferences` default extension | same file | The typed ergonomics, derived on top of the three requirements so **every conformer gets them free**: `value(_:forKey:)` / `setValue(_:forKey:)` (a `Codable` JSON bridge through `Data`) and `rawValue(_:forKey:)` / `setRawValue(_:forKey:)` (a `RawRepresentable` bridge, `RawValue: Codable`). |
| `NebulaDefaults` | `Architecture/Preferences/NebulaDefaults.swift` | The concrete `final class` façade over `UserDefaults`. Implements only the three byte-level requirements (each takes the `Mutex` lock for the duration of the `UserDefaults` call). `Sendable` derived, **no `@unchecked`**. |

Tests: `ArchitecturePreferencesTests.swift` (17) — byte-level round-trip, Codable round-trip + absent→nil + corrupt→`DecodingError`, RawRepresentable String/Int round-trip + unmappable-raw→nil, an `InMemoryPrefs` `final class` proving the default extension works on a non-`UserDefaults` conformer, an existential `any NebulaPreferences` holding both impls, and a Sendable-across-`Task` + 50-task concurrent-access smoke test. 574 Nebula tests / 118 suites green; zero concurrency warnings.

## Design decisions

- **`UserDefaults` is `@_nonSendable(_assumed)`** (verified against the Xcode 27 Beta 3 SDK — its `Sendable` conformance is unavailable in the Swift 6 language mode). It is *thread-safe* in practice, but the compiler can't prove it, so a plain `let defaults: UserDefaults` struct would not be `Sendable`. The `Mutex<UserDefaults>` provides the synchronization boundary the compiler needs — **region-based isolation (SE-0414), the CLAUDE.md alternative to `@unchecked`**. Never `@unchecked Sendable` on a Nebula-defined type.
- **`final class`, not `struct`.** `Mutex<T>` is `~Copyable` and `@_staticExclusiveOnly`; a `Mutex`-typed stored property propagates `~Copyable` to a *struct* owner (CLAUDE.md) — bad ergonomics for a façade (no copy, no `Equatable`). A `final class` absorbs the `~Copyable` `Mutex` behind a copyable reference and **derives `Sendable` with no `@unchecked`** (compiler-verified — the `NebulaSpyUseCase` / N1 `SendableBox` precedent). Reference semantics is correct here anyway: you want to share the underlying `UserDefaults`.
- **The init parameter is `sending` (SE-0430).** `Mutex`'s initializer takes the value `sending` (it holds it across isolation boundaries), and `UserDefaults` is not `Sendable`, so ownership must transfer at the call site: `init(_ defaults: sending UserDefaults = .standard)`. This is a **safety feature** — once you hand a `UserDefaults` to `NebulaDefaults`, the compiler rejects any further use of that instance (use-after-send), preventing two regions from racing on the same non-`Sendable` store. The `sending` modifier is placed before the type (`sending UserDefaults`), so it does **not** become an argument label — call sites stay `NebulaDefaults(suite)` / `NebulaDefaults()`.
- **The port's contract is three byte-level methods, not the full typed set.** Everything typed is a *default extension* on `data`/`setData`/`remove`, so a test double / iCloud KV / encrypted store conforms by implementing three methods and inherits `Codable`/`RawRepresentable` ergonomics. This is the architecture-seam point: the seam is tiny, the ergonomics are shared.
- **The Codable bridge uses plain `JSONEncoder`/`JSONDecoder` (Foundation), not `NebulaJSONEncoder`/`NebulaJSONDecoder`.** `JSONEncoder`/`JSONDecoder` are `Sendable` and constructed per call, keeping the preferences port decoupled from the gateway's encoder configuration (a preferences value shouldn't inherit the gateway's date-encoding strategy etc.).
- **Reads are lenient (`T?`), writes throw.** `value(_:forKey:)` returns `nil` for an absent key and throws `DecodingError` for corrupt data (absent vs corrupt is distinguishable). `setValue(_:forKey:)` throws `EncodingError` (a programmer error — a well-formed `Codable` type encodes). `setValue(nil)` / `setRawValue(nil)` removes the key. `rawValue` returns `nil` when the stored raw value doesn't map to a case (`R(rawValue:)` returns `nil`) — indistinguishable from absent, matching `UserDefaults` leniency.
- **Storage is JSON `Data`, not `UserDefaults`' native typed setters.** A value written through `setValue` is JSON-encoded `Data`; `UserDefaults.set(_:forKey:)` written directly is **not** readable through `value` (documented on the method). Uniform `Data` storage is what makes the port portable to non-`UserDefaults` stores.

## TDD fit (Wave N2)

- Each test uses an isolated `UserDefaults(suiteName:)` (unique per call via `UUID()`), handed to `NebulaDefaults` through the `sending` init — no `.standard` pollution, and the suite can't be touched afterward (the `sending` guarantee).
- `InMemoryPrefs` (`final class`, `Mutex<[String: Data]>`) is a non-`UserDefaults` conformer; its tests prove the `Codable`/`RawRepresentable` default extension is reusable on any conformer, not just `UserDefaults`. The existential test holds both impls in `[NebulaPreferences]` and round-trips a `Codable` through each.
- The concurrent-access test runs 50 child `Task`s through one `Sendable` `NebulaDefaults`, each writing a unique key and reading it back; the `Mutex` must serialize access (a race would crash or return a wrong value). Child tasks catch internally so the `addTask` closure stays non-throwing (`withTaskGroup` requires it).

## Notes / guardrails

- `UserDefaults` is Foundation → no new framework import, no binding-rule tension. The façade ships in Nebula.
- **Lean v0.4 surface** (Q6): no key-namespace policy, no change observation (`NotificationCenter` KVO on `UserDefaults`), no suite-management API. Those wait for a use.
- The `sending` init means a caller cannot share one `UserDefaults` between their own code and `NebulaDefaults`. That is intentional. For a shared store, the caller conforms to `NebulaPreferences` themselves and holds the `UserDefaults`.
- `NebulaDefaults` does not add a `NebulaError` mapping — preferences failures surface as `EncodingError`/`DecodingError` (Codable) directly. No new `NebulaError.Kind` case (closed-enum rule).

## Build gate (Wave N2)

- Nebula: `swift build && swift test && swift build -c release` → 574 tests / 118 suites, zero warnings, release clean. New code has no `#if os()` (Foundation + Synchronization only) → per-platform risk nil; full 5-platform `xcodebuild` pass deferred to N4.
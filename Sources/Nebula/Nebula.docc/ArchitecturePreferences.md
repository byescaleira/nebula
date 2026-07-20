# Preferences

A `Sendable` key-value preferences port and a `Mutex`-wrapped `UserDefaults` façade.

## Overview

Nebula ships the seam **and** a concrete Foundation adapter. ``NebulaPreferences``
is the architecture seam — a `Sendable` protocol with three byte-level requirements
(``NebulaPreferences/data(forKey:)`` / ``NebulaPreferences/setData(_:forKey:)`` /
``NebulaPreferences/remove(forKey:)``). The typed ergonomics are a **default
extension** built on those three, so every conformer gets them for free:

- ``NebulaPreferences/value(_:forKey:)`` / ``NebulaPreferences/setValue(_:forKey:)``
  — a `Codable` bridge (JSON through `Data`);
- ``NebulaPreferences/rawValue(_:forKey:)`` / ``NebulaPreferences/setRawValue(_:forKey:)``
  — a `RawRepresentable` bridge (`RawValue: Codable`).

``NebulaDefaults`` is the concrete façade over `UserDefaults`. An app swaps the
backing store — an iCloud key-value store, an encrypted store, a test double — by
conforming to ``NebulaPreferences`` directly and implementing only the three
byte-level methods.

```swift
let prefs: NebulaPreferences = NebulaDefaults()
try prefs.setValue(Settings(theme: .dark, volume: 7), forKey: "settings")
let settings: Settings? = try prefs.value(Settings.self, forKey: "settings")

try prefs.setRawValue(Theme.dark, forKey: "theme")
let theme: Theme? = try prefs.rawValue(Theme.self, forKey: "theme")
```

### Why a `Mutex` and a `final class`

`UserDefaults` is thread-safe but the SDK marks it `@_nonSendable(_assumed)` — its
`Sendable` conformance is unavailable in the Swift 6 language mode — so a plain
`let defaults: UserDefaults` struct would not be `Sendable`. ``NebulaDefaults``
wraps it in a `Mutex<UserDefaults>` (region-based isolation, the alternative to
`@unchecked`), and is a `final class` so the `~Copyable` `Mutex` is absorbed
behind a copyable, `Sendable` reference (derived, **no `@unchecked`**).

The initializer takes the `UserDefaults` `sending` (SE-0430): ownership transfers
at the call site, so the compiler rejects any further use of that instance — two
regions can't race on the same non-`Sendable` store. Pass a dedicated
`UserDefaults(suiteName:)`; `.standard` is the convenience default.

```swift
let suite = UserDefaults(suiteName: "com.acme.prefs")!
let prefs = NebulaDefaults(suite)   // `suite` may not be used after this line
```

## Topics

### Port
- ``NebulaPreferences``
- ``NebulaPreferences/data(forKey:)``
- ``NebulaPreferences/setData(_:forKey:)``
- ``NebulaPreferences/remove(forKey:)``

### Codable bridge (default extension)
- ``NebulaPreferences/value(_:forKey:)``
- ``NebulaPreferences/setValue(_:forKey:)``

### RawRepresentable bridge (default extension)
- ``NebulaPreferences/rawValue(_:forKey:)``
- ``NebulaPreferences/setRawValue(_:forKey:)``

### Concrete façade
- ``NebulaDefaults``
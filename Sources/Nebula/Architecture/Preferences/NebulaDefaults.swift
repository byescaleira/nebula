//
//  NebulaDefaults.swift
//  Nebula
//
//  Wave N2 — Clean Architecture toolkit. The concrete ``NebulaPreferences``
//  façade over `UserDefaults`. `UserDefaults` is thread-safe but the SDK marks
//  it `@_nonSendable(_assumed)` (verified against the Xcode 27 Beta 3 SDK — its
//  `Sendable` conformance is unavailable in the Swift 6 language mode), so a
//  plain `let defaults: UserDefaults` struct would not be `Sendable`. Wrapping
//  it in a `Mutex<UserDefaults>` gives the compiler a synchronization boundary
//  (region-based isolation, the CLAUDE.md alternative to `@unchecked`).
//
//  `Mutex<T>` is `~Copyable` and `@_staticExclusiveOnly`, so a `Mutex`-typed
//  stored property would propagate `~Copyable` to a *struct* owner (CLAUDE.md).
//  A `final class` absorbs the `~Copyable` `Mutex` behind a copyable reference
//  and derives `Sendable` with **no `@unchecked`** (compiler-verified — the
//  `NebulaSpyUseCase` / N1 `SendableBox` precedent). See
//  vault/03-padroes/nebula-preferences.md.
//

import Foundation
import Synchronization

/// The concrete ``NebulaPreferences`` façade over `UserDefaults`.
///
/// A `final class` wrapping a `Mutex<UserDefaults>`. `UserDefaults` is
/// thread-safe but not `Sendable` in Swift 6 (`@_nonSendable(_assumed)`), so the
/// `Mutex` provides the synchronization boundary the compiler needs — and the
/// `final class` absorbs the `~Copyable` `Mutex` behind a copyable, `Sendable`
/// reference (derived, **no `@unchecked`**). Every accessor takes the lock for
/// the duration of the `UserDefaults` call.
///
/// Typed `Codable` / `RawRepresentable` access comes from the
/// ``NebulaPreferences`` default extension; this type implements only the three
/// byte-level requirements. For a test double, an iCloud key-value store, or an
/// encrypted store, conform to ``NebulaPreferences`` directly.
///
/// ```swift
/// let prefs: NebulaPreferences = NebulaDefaults()
/// try prefs.setValue(Settings(theme: .dark, volume: 7), forKey: "settings")
/// let settings: Settings? = try prefs.value(Settings.self, forKey: "settings")
/// ```
public final class NebulaDefaults: NebulaPreferences {

    private let mutex: Mutex<UserDefaults>

    /// Creates a façade over `defaults` (`.standard` by default).
    ///
    /// `defaults` is a `sending` parameter (SE-0430): `Mutex`'s initializer
    /// takes the value `sending` (it holds it across isolation boundaries), and
    /// `UserDefaults` is not `Sendable`, so ownership must transfer at the call
    /// site. This is a **safety feature** — once you hand a `UserDefaults` to
    /// `NebulaDefaults`, the compiler rejects any further use of that instance
    /// (a use-after-send), preventing two regions from racing on the same
    /// non-`Sendable` store. Pass a dedicated `UserDefaults(suiteName:)` per
    /// façade; `.standard` is the convenience default.
    public init(_ defaults: sending UserDefaults = .standard) {
        self.mutex = Mutex(defaults)
    }

    public func data(forKey key: String) -> Data? {
        mutex.withLock { $0.data(forKey: key) }
    }

    public func setData(_ value: Data?, forKey key: String) {
        mutex.withLock { $0.set(value, forKey: key) }
    }

    public func remove(forKey key: String) {
        mutex.withLock { $0.removeObject(forKey: key) }
    }
}
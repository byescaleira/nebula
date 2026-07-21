//
//  NebulaLocalFeatureFlags.swift
//  Nebula
//
//  Wave N14 — Clean Architecture toolkit. The concrete ``NebulaFeatureFlags``
//  façade over an in-memory `[String: NebulaFlagValue]` override map. The store
//  is a `Sendable` value type (`[String: NebulaFlagValue]` derives `Sendable`),
//  so — unlike ``NebulaDefaults`` (whose `UserDefaults` is `@_nonSendable`
//  and needs a `sending` init) — the `Mutex` here wraps a plain value and the
//  initializer takes it by value (no `sending`).
//
//  `Mutex<T>` is `~Copyable` and `@_staticExclusiveOnly`, so a `Mutex`-typed
//  stored property would propagate `~Copyable` to a *struct* owner (CLAUDE.md).
//  A `final class` absorbs the `~Copyable` `Mutex` behind a copyable reference
//  and derives `Sendable` with **no `@unchecked`** (the ``NebulaDefaults``
//  precedent). Persistence (`NebulaDefaults`-backed overrides) is deferred to a
//  follow-up — this wave ships the in-memory façade only. See
//  vault/03-padroes/nebula-feature-flags.md.
//

import Foundation
import Synchronization

/// The concrete ``NebulaFeatureFlags`` façade over an in-memory override map.
///
/// A `final class` wrapping a `Mutex<[String: NebulaFlagValue]>`. The store is a
/// `Sendable` value type, so the `Mutex` provides a synchronization boundary the
/// compiler is happy with and the `final class` absorbs the `~Copyable` `Mutex`
/// behind a copyable, `Sendable` reference (derived, **no `@unchecked`**). Every
/// accessor takes the lock for the duration of the dictionary access. Reference
/// semantics is the right shape — an app shares one override store across the
/// composition root and mutates it at runtime.
///
/// Typed `bool` / `string` / `int` / `double` / `number` / `json` access comes
/// from the ``NebulaFeatureFlags`` default extension; this type implements only
/// the single ``value(forKey:)`` requirement plus the mutation surface.
///
/// ```swift
/// let local = NebulaLocalFeatureFlags()
/// local.setValue(.bool(true), forKey: "new_dashboard")
/// let on: Bool? = local.bool(forKey: "new_dashboard")   // true
/// local.removeValue(forKey: "new_dashboard")
/// ```
public final class NebulaLocalFeatureFlags: NebulaFeatureFlags {

    private let mutex: Mutex<[String: NebulaFlagValue]>

    /// Creates a façade seeded with `flags` (empty by default).
    public init(_ flags: [String: NebulaFlagValue] = [:]) {
        self.mutex = Mutex(flags)
    }

    public func value(forKey key: String) -> NebulaFlagValue? {
        mutex.withLock { $0[key] }
    }

    /// Stores `value` for `key`, or removes the key when `value` is `nil`.
    public func setValue(_ value: NebulaFlagValue?, forKey key: String) {
        mutex.withLock { (store: inout [String: NebulaFlagValue]) -> Void in
            if let value {
                store[key] = value
            } else {
                store.removeValue(forKey: key)
            }
        }
    }

    /// Removes any value stored for `key` (a no-op when absent).
    public func removeValue(forKey key: String) {
        mutex.withLock { (store: inout [String: NebulaFlagValue]) -> Void in
            store.removeValue(forKey: key)
        }
    }

    /// Removes every stored override.
    public func removeAll() {
        mutex.withLock { (store: inout [String: NebulaFlagValue]) -> Void in store.removeAll() }
    }
}
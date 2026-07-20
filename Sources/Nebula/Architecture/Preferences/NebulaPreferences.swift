//
//  NebulaPreferences.swift
//  Nebula
//
//  Wave N2 — Clean Architecture toolkit. The preferences seam: a `Sendable`
//  key-value port an app conforms to swap the backing store (UserDefaults,
//  iCloud key-value store, an encrypted store, a test double). The byte-level
//  contract is just `data(forKey:)` / `setData(_:forKey:)` / `remove(forKey:)`;
//  the typed `Codable` / `RawRepresentable` ergonomics are derived in a default
//  extension so every conformer gets them for free. See
//  vault/03-padroes/nebula-preferences.md.
//

import Foundation

/// A `Sendable` key-value preferences port.
///
/// The architecture seam for persisted user preferences. The contract is
/// intentionally tiny — three `Data`-level requirements — so an app can swap the
/// backing store without reimplementing typed accessors:
/// - ``data(forKey:)`` / ``setData(_:forKey:)`` — the byte-level get/set;
/// - ``remove(forKey:)`` — delete.
///
/// Everything else is a **default extension** built on those three:
/// - ``value(_:forKey:)`` / ``setValue(_:forKey:)`` — a `Codable` bridge
///   (JSON-encode/decode through `Data`);
/// - ``rawValue(_:forKey:)`` / ``setRawValue(_:forKey:)`` — a `RawRepresentable`
///   bridge (store the `rawValue`, which must itself be `Codable`).
///
/// The concrete Foundation façade is ``NebulaDefaults`` (a `Mutex`-wrapped
/// `UserDefaults`). A test double, an `NSUbiquitousKeyValueStore` adapter, or an
/// encrypted store conforms the same way. There is **no** key-namespace policy
/// and **no** change observation yet — the v0.4 surface is lean.
public protocol NebulaPreferences: Sendable {

    /// Returns the raw `Data` stored for `key`, or `nil` when absent.
    func data(forKey key: String) -> Data?

    /// Stores `value` for `key`, or removes the key when `value` is `nil`.
    func setData(_ value: Data?, forKey key: String)

    /// Removes any value stored for `key` (a no-op when absent).
    func remove(forKey key: String)
}

public extension NebulaPreferences {

    /// Decodes a `Codable` value stored for `key`.
    ///
    /// Returns `nil` when the key is absent. Throws `DecodingError` when stored
    /// data is present but corrupt — distinct from "absent", so a caller can
    /// distinguish a missing preference from a bad one. The bridge is JSON
    /// through ``data(forKey:)``; it does not use `UserDefaults`' native typed
    /// getters, so a value written by `UserDefaults.set(_:forKey:)` directly is
    /// **not** readable here (write through ``setValue(_:forKey:)`` too).
    func value<T: Codable>(_ type: T.Type, forKey key: String) throws -> T? {
        guard let data = data(forKey: key) else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// JSON-encodes `value` and stores it for `key`; removes the key when `nil`.
    ///
    /// Throws `EncodingError` if `value` cannot be encoded (a programmer error
    /// — a well-formed `Codable` type encodes). `JSONEncoder`/`JSONDecoder` are
    /// `Sendable` and constructed per call, so the bridge stays decoupled from
    /// the gateway's `NebulaJSONEncoder`/`NebulaJSONDecoder` configuration.
    func setValue<T: Codable>(_ value: T?, forKey key: String) throws {
        if let value {
            setData(try JSONEncoder().encode(value), forKey: key)
        } else {
            remove(forKey: key)
        }
    }

    /// Reads a `RawRepresentable` value whose `RawValue` is `Codable`.
    ///
    /// Decodes the `rawValue` via ``value(_:forKey:)`` and reconstitutes the
    /// case. Returns `nil` when the key is absent **or** the stored raw value
    /// does not map to a case (`R(rawValue:)` returns `nil`) — the two are
    /// indistinguishable here, matching `UserDefaults` leniency.
    func rawValue<R: RawRepresentable>(_ type: R.Type, forKey key: String) throws -> R? where R.RawValue: Codable {
        guard let raw = try value(R.RawValue.self, forKey: key) else { return nil }
        return R(rawValue: raw)
    }

    /// Stores the `rawValue` of a `RawRepresentable` value (removes the key when `nil`).
    func setRawValue<R: RawRepresentable>(_ value: R?, forKey key: String) throws where R.RawValue: Codable {
        try setValue(value?.rawValue, forKey: key)
    }
}
//
//  NebulaSecureStore.swift
//  Nebula
//
//  Wave N9 — App-readiness. The secure-storage seam: a `Sendable` key-value port
//  an app conforms to swap the backing store (Keychain, an encrypted store, a
//  test double). The byte-level contract is `data(forKey:)` / `setData(_:forKey:)`
//  / `remove(forKey:)` — the same three as ``NebulaPreferences``, but `throws`,
//  because secure storage has real failure modes (auth failed, device locked,
//  missing entitlement). The typed `Codable` / `RawRepresentable` ergonomics are
//  derived in a default extension so every conformer gets them for free. The
//  concrete Security façade is ``NebulaKeychain``. See
//  vault/03-padroes/nebula-keychain.md and nebula-keychain-auth.md.
//
//  `NebulaSecureStore` is a **distinct** port from ``NebulaPreferences``: a
//  Keychain conformer must not be a drop-in for a prefs store (different threat
//  model — secrets vs. user-tunable preferences). An app injects a secure store
//  and a preferences store as separate seams.
//

import Foundation

/// A `Sendable` secure-storage port.
///
/// The architecture seam for persisted secrets (credentials, tokens, keys).
/// The contract is intentionally tiny — three `Data`-level requirements — so an
/// app can swap the backing store without reimplementing typed accessors:
/// - ``data(forKey:)`` — read raw bytes (`nil` when absent);
/// - ``setData(_:forKey:)`` — write raw bytes (or remove when `nil`);
/// - ``remove(forKey:)`` — delete.
///
/// Unlike ``NebulaPreferences``, every requirement `throws`: secure storage can
/// fail in ways a `UserDefaults` store cannot (authentication failure, the
/// device being locked, a missing entitlement). `data(forKey:)` returns `nil`
/// for an absent key and `throws` for a genuine failure — a caller can
/// distinguish "no secret" from "could not read the secret".
///
/// Everything else is a **default extension** built on those three:
/// - ``value(_:forKey:)`` / ``setValue(_:forKey:)`` — a `Codable` bridge
///   (JSON-encode/decode through `Data`);
/// - ``rawValue(_:forKey:)`` / ``setRawValue(_:forKey:)`` — a `RawRepresentable`
///   bridge (store the `rawValue`, which must itself be `Codable`).
///
/// The concrete Security façade is ``NebulaKeychain``. A test double or an
/// encrypted store conforms the same way.
public protocol NebulaSecureStore: Sendable {

    /// Returns the raw `Data` stored for `key`, or `nil` when absent.
    ///
    /// Throws a ``NebulaKeychainError`` (or a conformer-specific `NebulaFailure`)
    /// when the store cannot be read — authentication failure, the device being
    /// locked (`errSecInteractionNotAllowed`), or a missing entitlement. Absent
    /// is **not** an error.
    func data(forKey key: String) throws -> Data?

    /// Stores `value` for `key`, or removes the key when `value` is `nil`.
    ///
    /// Throws when the store cannot be written. A conformer SHOULD prefer
    /// updating an existing item in place over delete-then-add (preserves
    /// access control; see ``NebulaKeychain``).
    func setData(_ value: Data?, forKey key: String) throws

    /// Removes any value stored for `key` (a no-op when absent).
    func remove(forKey key: String) throws
}

public extension NebulaSecureStore {

    /// Decodes a `Codable` value stored for `key`.
    ///
    /// Returns `nil` when the key is absent. Throws `DecodingError` when stored
    /// data is present but corrupt — distinct from "absent", so a caller can
    /// distinguish a missing secret from a bad one. Also rethrows any store
    /// failure from ``data(forKey:)``. The bridge is JSON through
    /// ``data(forKey:)``; `JSONEncoder`/`JSONDecoder` are `Sendable` and
    /// constructed per call, so the bridge stays decoupled from the gateway's
    /// `NebulaJSONEncoder`/`NebulaJSONDecoder` configuration.
    func value<T: Codable>(_ type: T.Type, forKey key: String) throws -> T? {
        guard let data = try data(forKey: key) else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// JSON-encodes `value` and stores it for `key`; removes the key when `nil`.
    ///
    /// Throws `EncodingError` if `value` cannot be encoded (a programmer error
    /// — a well-formed `Codable` type encodes), and rethrows any store failure
    /// from ``setData(_:forKey:)``.
    func setValue<T: Codable>(_ value: T?, forKey key: String) throws {
        if let value {
            try setData(try JSONEncoder().encode(value), forKey: key)
        } else {
            try remove(forKey: key)
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
//
//  NebulaFeatureFlags.swift
//  Nebula
//
//  Wave N14 — Clean Architecture toolkit. The feature-flag resolution port: a
//  `Sendable` protocol with a single ``value(forKey:)`` requirement returning a
//  ``NebulaFlagValue``, plus a default extension of typed accessors
//  (`bool`/`string`/`int`/`double`/`number`/`json`) built on it — every conformer
//  gets the ergonomics for free. The seam model mirrors ``NebulaPreferences``
//  (one low-level requirement + default-extension typed bridges). There is no
//  Apple-native remote-config/feature-flag API, so a remote flag is necessarily
//  a port the app conforms; `dependencies: []` forbids Firebase / LaunchDarkly.
//  See vault/03-padroes/nebula-feature-flags.md.
//

import Foundation

/// A `Sendable` feature-flag resolution port.
///
/// The architecture seam for reading feature flags. The contract is
/// intentionally tiny — one ``NebulaFlagValue``-returning requirement — so an
/// app can swap the backing store (an in-memory override map, a fetched remote
/// cache, a `NebulaDefaults`-backed persistent store) without reimplementing
/// typed accessors:
/// - ``value(forKey:)`` — the raw lookup (the only requirement);
/// - ``bool(forKey:)`` / ``string(forKey:)`` / ``int(forKey:)`` /
///   ``double(forKey:)`` — typed payload accessors;
/// - ``number(forKey:)`` — coerces `.int` or `.double` to `Double`;
/// - ``json(_:forKey:)`` — decodes a `.json(_:)` blob into a `Decodable` type.
///
/// Everything but ``value(forKey:)`` is a **default extension** built on it, so
/// every conformer — the in-memory ``NebulaLocalFeatureFlags`` façade, a remote
/// fetcher conforming to ``NebulaRemoteFeatureFlags``, the priority-ordered
/// ``NebulaCompositeFeatureFlags`` — gets the typed ergonomics for free.
///
/// `value(forKey:)` is non-throwing (a lookup that may be absent); only
/// ``json(_:forKey:)`` throws, because decoding may fail. Flag errors surface
/// as `DecodingError` from the `json` bridge — Nebula adds no new
/// ``NebulaError/Kind`` case for feature flags.
public protocol NebulaFeatureFlags: Sendable {

    /// The raw flag value for `key`, or `nil` when absent.
    func value(forKey key: String) -> NebulaFlagValue?
}

public extension NebulaFeatureFlags {

    /// Returns the `Bool` payload for `key`, or `nil` when the flag is absent or
    /// holds a non-`.bool` value. Non-throwing — a lookup, not a decode.
    func bool(forKey key: String) -> Bool? {
        if case .bool(let value) = value(forKey: key) { return value }
        return nil
    }

    /// Returns the `String` payload for `key`, or `nil` when the flag is absent
    /// or holds a non-`.string` value.
    func string(forKey key: String) -> String? {
        if case .string(let value) = value(forKey: key) { return value }
        return nil
    }

    /// Returns the `Int` payload for `key`, or `nil` when the flag is absent or
    /// holds a non-`.int` value. `.double` is **not** coerced to `Int` — use
    /// ``number(forKey:)`` for any-number access.
    func int(forKey key: String) -> Int? {
        if case .int(let value) = value(forKey: key) { return value }
        return nil
    }

    /// Returns the `Double` payload for `key`, or `nil` when the flag is absent
    /// or holds a non-`.double` value. `.int` is **not** coerced to `Double`
    /// here — use ``number(forKey:)`` for any-number access.
    func double(forKey key: String) -> Double? {
        if case .double(let value) = value(forKey: key) { return value }
        return nil
    }

    /// Returns the numeric payload for `key` as `Double`, accepting either
    /// `.double` or `.int`; `nil` when the flag is absent or non-numeric. This is
    /// the "any number" accessor — `int(forKey:)` / `double(forKey:)` return
    /// only their own case, with no silent coercion.
    func number(forKey key: String) -> Double? {
        switch value(forKey: key) {
        case .double(let value): return value
        case .int(let value): return Double(value)
        default: return nil
        }
    }

    /// Decodes a `.json(_:)` flag for `key` into `T`.
    ///
    /// Returns `nil` when the key is absent or holds a non-`.json` value. Throws
    /// `DecodingError` when the stored `Data` is present but cannot be decoded
    /// into `T` — distinct from "absent", so a caller can distinguish a missing
    /// flag from a malformed one. The bridge constructs a `JSONDecoder` per
    /// call; it is `Sendable` and deliberately decoupled from the gateway's
    /// `NebulaJSONDecoder` configuration (the ``NebulaPreferences`` rationale).
    func json<T: Decodable>(_ type: T.Type, forKey key: String) throws -> T? {
        guard case .json(let data) = value(forKey: key) else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
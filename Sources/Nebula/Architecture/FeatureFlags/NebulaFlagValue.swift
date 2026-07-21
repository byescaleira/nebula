//
//  NebulaFlagValue.swift
//  Nebula
//
//  Wave N14 — Clean Architecture toolkit. The storage representation for a
//  feature flag: a `Sendable` value enum that a flag port resolves per key.
//  There is no Apple-native remote-config or feature-flag API (zero
//  `FeatureFlag`/`RemoteConfig`/`RolloutConfig` hits in `Foundation.swiftmodule`,
//  Xcode 27 Beta 3), so Nebula ships the Foundation-tier pattern — this value
//  type plus a resolution port (``NebulaFeatureFlags``), an in-memory façade
//  (``NebulaLocalFeatureFlags``), a remote-fetch port
//  (``NebulaRemoteFeatureFlags``), and a priority-ordered composite
//  (``NebulaCompositeFeatureFlags``). `dependencies: []` forbids Firebase /
//  LaunchDarkly, so a remote flag is necessarily a port the app conforms. See
//  vault/03-padroes/nebula-feature-flags.md.
//

import Foundation

/// A `Sendable` feature-flag value.
///
/// The storage representation resolved per key by ``NebulaFeatureFlags``. Five
/// payload kinds cover the value shapes a flag typically carries:
/// - ``bool(_:)`` — an on/off toggle;
/// - ``string(_:)`` — a string variant (a copy, an endpoint, a variant key);
/// - ``int(_:)`` — an integer (a limit, a count, a version's major);
/// - ``double(_:)`` — a floating-point (a rollout fraction, a threshold);
/// - ``json(_:)`` — an opaque `Data` blob the ``NebulaFeatureFlags/json(_:forKey:)``
///   bridge decodes into a `Decodable` type.
///
/// `.int` and `.double` are stored distinctly (no silent precision loss); the
/// ``NebulaFeatureFlags/number(forKey:)`` accessor coerces either to `Double`.
/// The enum is `Sendable`, `Equatable`, and `Hashable` by derived conformance
/// (every associated value is) — **no `@unchecked`** — and `Codable` is
/// **not** adopted yet; it arrives with the `NebulaDefaults`-backed persistence
/// follow-up (adding it later is additive).
public enum NebulaFlagValue: Sendable, Equatable, Hashable, CustomStringConvertible {

    /// A Boolean toggle.
    case bool(Bool)

    /// A string variant.
    case string(String)

    /// An integer value.
    case int(Int)

    /// A floating-point value.
    case double(Double)

    /// An opaque `Data` blob, decoded via the ``NebulaFeatureFlags/json(_:forKey:)``
    /// bridge into a `Decodable` type.
    case json(Data)

    public var description: String {
        switch self {
        case .bool(let value): "NebulaFlagValue.bool(\(value))"
        case .string(let value): "NebulaFlagValue.string(\"\(value)\")"
        case .int(let value): "NebulaFlagValue.int(\(value))"
        case .double(let value): "NebulaFlagValue.double(\(value))"
        case .json(let data): "NebulaFlagValue.json(\(data.count) bytes)"
        }
    }
}
//
//  NebulaMetricValue.swift
//  Nebula
//
//  Wave N19a — CloudKit-backed observability suite. The metric attribute value
//  type: a `Sendable`, `Equatable`, `Hashable` sum type mirroring the shape of
//  `NebulaFlagValue` (bool / string / int / double / json-payload). Carried as
//  the `attributes` dictionary value on a ``NebulaMetricEvent``. See
//  vault/03-padroes/nebula-cloudkit-observability.md.
//

import Foundation

/// A `Sendable` metric attribute value.
///
/// A sum type for the per-event `attributes` map on ``NebulaMetricEvent``, so a
/// CloudKit metrics adapter (or any other backend) can carry typed scalar
/// dimensions without committing to a single primitive. Mirrors the shape of
/// `NebulaFlagValue` (bool / string / int / double / json-payload).
///
/// All five payloads are `Sendable`, `Equatable`, and `Hashable`, so all three
/// conformances are derived (no `@unchecked`, no authored `==` / `hash(into:)`).
public enum NebulaMetricValue: Sendable, Equatable, Hashable, CustomStringConvertible {
    /// A boolean attribute.
    case bool(Bool)
    /// A string attribute.
    case string(String)
    /// An integer attribute.
    case int(Int)
    /// A floating-point attribute.
    case double(Double)
    /// An arbitrary JSON payload, carried as raw `Data` (the adapter encodes).
    case json(Data)

    /// A debugging description in the `NebulaMetricValue.bool(true)` style —
    /// the case name plus the payload's `String(describing:)` form. For
    /// ``json(_:)` the payload's byte count is shown (not the raw bytes), so
    /// large payloads do not flood logs.
    public var description: String {
        switch self {
        case .bool(let value): return "NebulaMetricValue.bool(\(value))"
        case .string(let value): return "NebulaMetricValue.string(\(value))"
        case .int(let value): return "NebulaMetricValue.int(\(value))"
        case .double(let value): return "NebulaMetricValue.double(\(value))"
        case .json(let data): return "NebulaMetricValue.json(\(data.count) bytes)"
        }
    }
}

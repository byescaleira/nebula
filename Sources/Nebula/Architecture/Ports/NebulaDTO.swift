//
//  NebulaDTO.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. The Data Transfer Object marker: the
//  "simple data structures" that cross Clean Architecture boundaries per
//  Uncle Bob ("We don't want to cheat and pass Entities or Database rows"). A
//  bare `Sendable` marker in v1 — Nebula does not force `Codable` or
//  `Equatable` on the type, since DTOs cross both wire (`Codable`) and layer
//  (`Equatable`) boundaries on the consumer's terms. Docs recommend DTOs
//  conform to `Equatable` for test assertions. See
//  vault/03-padroes/nebula-clean-architecture-toolkit.md.
//

import Foundation

/// A marker for a **Data Transfer Object**: the "simple data structure" that
/// crosses a Clean Architecture boundary.
///
/// Per the dependency rule, data crossing a boundary is a plain data
/// structure — not an entity, not a database row. A DTO is the shape a use
/// case hands to an output port and the shape an adapter receives from an
/// input port.
///
/// A bare `Sendable` marker in v1. Nebula does **not** force `Codable` (a DTO
/// may cross an in-process layer boundary that never serializes) or
/// `Equatable`; both are the consumer's decision. **Recommendation**: conform
/// DTOs to `Equatable` so test assertions (`#expect(dtoA == dtoB)`) are
/// ergonomic, and to `Codable` only when the DTO actually crosses a wire.
public protocol NebulaDTO: Sendable {}
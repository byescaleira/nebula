//
//  NebulaAggregate.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. An **Aggregate Root** (DDD): the
//  consistency boundary around a cluster of entities. `NebulaAggregate` is a
//  marker protocol that refines ``NebulaEntity`` with no additional requirements
//  — an aggregate is simply the entity the outside world is allowed to hold a
//  reference to and persist as a unit. See
//  vault/03-padroes/nebula-validation-invariants.md.
//

import Foundation

/// A marker for a Clean Architecture **Aggregate Root**.
///
/// An aggregate root is the single entity a repository persists and the only
/// entity the outside world may hold a direct reference to; it owns the
/// invariants of its cluster. `NebulaAggregate` adds no requirements over
/// ``NebulaEntity`` — it is a label so that repository capability protocols
/// (``NebulaWritableRepository``/``NebulaDeletableRepository``) and future
/// aggregate-level invariant validation can constrain to "the root of a
/// consistency boundary" without inspecting its shape.
///
/// ```swift
/// struct Order: NebulaAggregate {
///     typealias ID = NebulaID<Order>
///     let id: ID
///     var lines: [OrderLine]   // child entities, reachable only via the root
/// }
/// ```
public protocol NebulaAggregate: NebulaEntity {}
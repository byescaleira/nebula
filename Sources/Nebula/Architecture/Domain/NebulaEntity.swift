//
//  NebulaEntity.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. The Entity marker: a `Sendable`,
//  `Identifiable` value whose `ID` is itself `Sendable`. Entities carry
//  enterprise business rules and an identity; they are NOT `Equatable` by
//  marker contract (two entities with the same ID may differ in mutable
//  state — equality is the entity's own decision). See
//  vault/03-padroes/nebula-validation-invariants.md.
//

import Foundation

/// A marker for a Clean Architecture **Entity**: a `Sendable`, `Identifiable`
/// value carrying enterprise business rules and a stable identity.
///
/// Refines `Identifiable` with `ID: Sendable` so the identity can cross actor
/// boundaries inside `@Sendable` handlers. Deliberately does **not** refine
/// `Equatable`: entity equality is the entity's own decision (identity
/// equality vs. value equality), so the toolkit leaves it unconstrained.
///
/// The entity's `ID` is typically a ``NebulaID``-typed phantom:
///
/// ```swift
/// struct Account: NebulaEntity {
///     typealias ID = NebulaID<Account>
///     let id: ID
///     let balance: Decimal
/// }
/// ```
public protocol NebulaEntity: Sendable, Identifiable where ID: Sendable, ID: Hashable {}
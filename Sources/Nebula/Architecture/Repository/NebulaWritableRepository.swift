//
//  NebulaWritableRepository.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. The write-side capability: `save(_:)`.
//  Add-or-replace semantics (an entity with the same id replaces the prior
//  record). Deliberately NO `update` verb — Fowler's Repository has no `update`,
//  and a partial update is a use-case concern, not a repository concern.
//  `Entity: NebulaEntity`. See vault/03-padroes/nebula-repository.md.
//

import Foundation

/// A write-side repository capability: `save(_:)`.
///
/// Refines ``NebulaRepository`` with `Entity: NebulaEntity`. `save(_:)` is
/// add-or-replace: an entity with the same id replaces the prior record.
/// Deliberately **no** `update` verb — Fowler's Repository has no `update`, and
/// a partial-field update is an application (use-case) concern, not a
/// repository concern. A repository that needs partial updates models them as
/// read-modify-`save` inside a use case.
public protocol NebulaWritableRepository<Element>: NebulaRepository where Element: NebulaEntity {

    /// Saves `entity` (add-or-replace by id).
    func save(_ entity: Element) async throws
}
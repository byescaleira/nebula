//
//  NebulaDeletableRepository.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. The opt-in delete capability. A
//  separate protocol (not on the base) so repositories that are legitimately
//  append-only (audit logs, event stores) need not implement a trapping
//  `delete`. `Entity: NebulaEntity`. See vault/03-padroes/nebula-repository.md.
//

import Foundation

/// An opt-in delete capability for a repository.
///
/// A **separate** protocol (not refined onto ``NebulaWritableRepository``) so
/// repositories that are legitimately append-only (audit logs, immutable event
/// stores) need not implement a trapping `delete`. Refines
/// ``NebulaRepository`` with `Entity: NebulaEntity`.
public protocol NebulaDeletableRepository<Element>: NebulaRepository where Element: NebulaEntity {

    /// Deletes the entity with the given id. Deleting an absent id is a
    /// no-op (the app's concrete repository decides — this protocol only
    /// declares the seam).
    func delete(_ id: Element.ID) async throws
}
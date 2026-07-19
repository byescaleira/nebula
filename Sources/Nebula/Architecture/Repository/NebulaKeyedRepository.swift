//
//  NebulaKeyedRepository.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. The keyed-read capability: `find(id:)`.
//  A **protocol requirement** (not a default extension) so the app's concrete
//  repository overrides it with its own lookup. `Element: NebulaEntity` so the
//  `ID` type is known. See vault/03-padroes/nebula-repository.md.
//

import Foundation

/// A keyed-read repository capability: `find(id:)`.
///
/// Refines ``NebulaReadOnlyRepository`` with `Element: NebulaEntity` so the
/// entity's `ID` type is known. `find(id:)` is a **protocol requirement** (not
/// a default extension) so the app's concrete repository overrides it with its
/// own lookup (a default extension delegating to `stream()` would force a
/// full scan on every keyed repository and prevent an indexed implementation).
public protocol NebulaKeyedRepository<Element>: NebulaReadOnlyRepository where Element: NebulaEntity {

    /// Finds the element with the given id, returning `nil` when absent.
    func find(id: Element.ID) async throws -> Element?
}
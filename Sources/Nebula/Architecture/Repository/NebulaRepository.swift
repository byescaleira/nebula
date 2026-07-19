//
//  NebulaRepository.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. The Repository seam (Martin Fowler):
//  "Mediates between the domain and data mapping layers using a collection-like
//  interface for accessing domain objects." A base `Sendable` protocol carrying
//  the element type as a primary associated type so `any NebulaRepository<E>` is
//  itself `Sendable` (compiler-verified — no `@unchecked`). Capability
//  sub-protocols (read-only / writable / keyed / deletable) refine this; there
//  is NO CRUD mandate. See vault/03-padroes/nebula-repository.md.
//

import Foundation

/// The base Repository seam: a `Sendable` protocol carrying the element type.
///
/// Mediates between the domain and data-mapping layers (Fowler). Nebula ships
/// only the seams; the app provides the concrete repository (Core Data,
/// SQLite, in-memory, a remote API). The base protocol carries the element
/// type as a **primary associated type** so `any NebulaRepository<Account>`
/// is itself `Sendable` when `Account: Sendable` (compiler-verified — no
/// `@unchecked` on a Nebula type).
///
/// Capability sub-protocols refine this base — there is **no** CRUD mandate:
/// - ``NebulaReadOnlyRepository`` — `stream()` / `count()` (read models,
///   `Element` unconstrained);
/// - ``NebulaKeyedRepository`` — `find(id:)` for keyed entities;
/// - ``NebulaWritableRepository`` — `save(_:)` (add-or-replace, no `update`);
/// - ``NebulaDeletableRepository`` — `delete(_:)` (opt-in delete).
public protocol NebulaRepository<Element>: Sendable {
    /// The element this repository deals in (an entity or a read model).
    associatedtype Element: Sendable
}
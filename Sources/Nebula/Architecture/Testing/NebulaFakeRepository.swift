//
//  NebulaFakeRepository.swift
//  Nebula
//
//  Wave H — Clean Architecture toolkit. An in-memory fake repository for tests:
//  a `final class` generic over `Entity: NebulaEntity`, conforming to the
//  keyed / writable / deletable capabilities. Mutable state is guarded by a
//  `let Mutex`. `Sendable` is **derived** — the class is `final` with a single
//  immutable `let` property of a `Sendable` type (`Mutex` is `Sendable` when its
//  value is), so the compiler synthesizes `Sendable` with no `@unchecked` (the
//  class-over-struct choice mirrors ``NebulaMemoryLogHandler``: a `Mutex`-typed
//  stored property propagates `~Copyable` to an owning *struct*, so the shared
//  mutable container lives in a class). Decision #8. See
//  vault/07-metodologia/nebula-test-doubles.md.
//

import Foundation
import Synchronization

/// An in-memory fake repository for tests: keyed, writable, and deletable.
///
/// A `final class` generic over `Entity: NebulaEntity`, with mutable state
/// guarded by a `let Mutex<[Entity.ID: Entity]>`. `Sendable` is **derived**:
/// the class is `final` with a single immutable `let` property of a `Sendable`
/// type, so the compiler synthesizes `Sendable` with no `@unchecked` (the
/// class-over-struct choice mirrors ``NebulaMemoryLogHandler`` — a `Mutex`-typed
/// stored property would propagate `~Copyable` to an owning *struct*, so the
/// shared mutable container lives in a class).
///
/// `save(_:)` is add-or-replace by id; `delete(_:)` on an absent id is a no-op;
/// `stream()` snapshots the store and yields each element.
///
/// - Note: Ship in the app's test target when you prefer not to depend on
///   Nebula's test surface; the double is provided here for convenience
///   (decision #8 — Nebula ships Fake/Stub/Spy).
public final class NebulaFakeRepository<Entity: NebulaEntity>: NebulaKeyedRepository, NebulaWritableRepository, NebulaDeletableRepository {

    // The repository protocols' primary associated type is `Element`; alias the
    // semantic generic parameter `Entity` to it.
    public typealias Element = Entity

    private let storage = Mutex<[Entity.ID: Entity]>([:])

    /// Creates an empty fake repository.
    public init() {}

    // MARK: - NebulaKeyedRepository

    public func find(id: Entity.ID) async throws -> Entity? {
        storage.withLock { $0[id] }
    }

    // MARK: - NebulaReadOnlyRepository

    public func stream() -> AsyncThrowingStream<Entity, any Error> {
        // Snapshot under the lock, then yield outside it (an async continuation
        // cannot be driven from inside `withLock`).
        let snapshot = storage.withLock { Array($0.values) }
        return AsyncThrowingStream { continuation in
            for entity in snapshot { continuation.yield(entity) }
            continuation.finish()
        }
    }

    public func count() async throws -> Int {
        storage.withLock { $0.count }
    }

    // MARK: - NebulaWritableRepository

    public func save(_ entity: Entity) async throws {
        storage.withLock { $0[entity.id] = entity }
    }

    // MARK: - NebulaDeletableRepository

    public func delete(_ id: Entity.ID) async throws {
        storage.withLock { _ = $0.removeValue(forKey: id) }
    }
}
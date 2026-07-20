//
//  AuroraRepository.swift
//  Aurora
//
//  Wave N3 — the `@ModelActor`-backed repository adapter that conforms to
//  Nebula's Foundation-only `NebulaRepository` capability ports. SwiftData's
//  `ModelContext` and `@Model` classes are not `Sendable` (verified); the
//  `@ModelActor` macro gives an actor-isolated `ModelContext`, and the
//  ``AuroraEntityMapping`` bridges the non-`Sendable` `@Model` to the `Sendable`
//  ``NebulaEntity`` DTO that crosses the boundary. `import Aurora` from Nebula
//  is a hard compile error (Nebula declares no such dependency) — the Clean
//  Architecture dependency rule is compiler-enforced across packages. See
//  vault/03-padroes/nebula-data-network-architecture.md.
//

import Foundation
import SwiftData
import Nebula

/// A `@ModelActor`-backed repository adapter over SwiftData, conforming to
/// Nebula's `NebulaRepository` capability ports.
///
/// Generic over an ``AuroraEntityMapping`` (`Mapping`). The repository's
/// `Element` is `Mapping.Entity` (a ``NebulaEntity``). The `@ModelActor` macro
/// synthesizes the `ModelContext` isolation and `init(modelContainer:)`; the
/// mapping is type-level, so construction is just:
///
/// ```swift
/// let container = try ModelContainer(for: AccountRecord.self, configurations: .init(isStoredInMemoryOnly: true))
/// let repo = AuroraRepository<AccountMapping>(modelContainer: container)
/// let account = Account(id: .init(), balance: 100)
/// try await repo.save(account)
/// try await repo.find(id: account.id)            // → account
/// try await repo.count()                          // → 1
/// try await repo.delete(account.id)
/// ```
///
/// `stream()` is synchronous (it returns an `AsyncThrowingStream`, not `async`),
/// so it is `nonisolated` and spawns a `Task` that hops to the actor to fetch.
/// `count()` / `find(id:)` / `save(_:)` / `delete(_:)` are `async` and run on
/// the actor. SwiftData errors are rethrown untyped (Nebula's public-API
/// posture: untyped `throws`); an app that wants ``NebulaRepositoryError``
/// wraps at the use-case boundary.
@ModelActor
public actor AuroraRepository<Mapping: AuroraEntityMapping> where Mapping: Sendable {

    /// The repository's element — the Sendable domain DTO.
    public typealias Element = Mapping.Entity

    // MARK: NebulaReadOnlyRepository

    /// Streams all entities, fetching on the actor and mapping each `@Model`
    /// to the Sendable DTO.
    ///
    /// Synchronous (the port returns an `AsyncThrowingStream`, not `async`), so
    /// this method is `nonisolated` and spawns a `Task` that hops to the actor.
    /// Cancellation finishes the stream early.
    nonisolated public func stream() -> AsyncThrowingStream<Mapping.Entity, any Error> {
        AsyncThrowingStream { continuation in
            Task { [weak self] in
                guard let self else { continuation.finish(); return }
                await self.streamAll(into: continuation)
            }
        }
    }

    private func streamAll(into continuation: AsyncThrowingStream<Mapping.Entity, any Error>.Continuation) async {
        do {
            let models = try modelContext.fetch(Mapping.descriptor())
            for model in models { continuation.yield(Mapping.toEntity(model)) }
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    public func count() async throws -> Int {
        try modelContext.fetchCount(Mapping.descriptor())
    }

    // MARK: NebulaKeyedRepository

    public func find(id: Mapping.Entity.ID) async throws -> Mapping.Entity? {
        let models = try modelContext.fetch(Mapping.descriptor(for: id))
        return models.first.map(Mapping.toEntity)
    }

    // MARK: NebulaWritableRepository

    public func save(_ entity: Mapping.Entity) async throws {
        let models = try modelContext.fetch(Mapping.descriptor(for: entity.id))
        if let existing = models.first {
            Mapping.update(existing, from: entity)
        } else {
            _ = Mapping.insert(entity, in: modelContext)
        }
        try modelContext.save()
    }

    // MARK: NebulaDeletableRepository

    public func delete(_ id: Mapping.Entity.ID) async throws {
        let models = try modelContext.fetch(Mapping.descriptor(for: id))
        if let existing = models.first {
            modelContext.delete(existing)
            try modelContext.save()
        }
        // Deleting an absent id is a no-op (matches the port contract).
    }
}

// MARK: - Port conformances

extension AuroraRepository: NebulaRepository {}
extension AuroraRepository: NebulaReadOnlyRepository {}
extension AuroraRepository: NebulaKeyedRepository {}
extension AuroraRepository: NebulaWritableRepository {}
extension AuroraRepository: NebulaDeletableRepository {}
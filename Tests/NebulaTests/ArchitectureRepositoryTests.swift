//
//  ArchitectureRepositoryTests.swift
//  NebulaTests
//
//  Wave H2 — Clean Architecture toolkit repository tests (Swift Testing): the
//  capability protocols (read-only / keyed / writable / deletable) exercised
//  through an actor-backed concrete repository, `any NebulaRepository<E>`
//  Sendable, and the concrete-vs-protocol shape.
//

import Testing
import Foundation
import Nebula

// MARK: - Fixtures

private struct Account: NebulaEntity {
    typealias ID = NebulaID<Account>
    let id: ID
    var balance: Decimal
}

/// An actor-backed in-memory store (the "fakes with a store use an actor"
/// Sendable discipline — decision #8).
private actor AccountStore {
    private var byID: [Account.ID: Account] = [:]
    func all() -> [Account] { Array(byID.values) }
    func find(_ id: Account.ID) -> Account? { byID[id] }
    func save(_ a: Account) { byID[a.id] = a }
    func delete(_ id: Account.ID) { byID.removeValue(forKey: id) }
}

/// A concrete repository conforming to the keyed / writable / deletable
/// capabilities. The app provides this; the test mirrors that shape.
private struct AccountRepository: NebulaKeyedRepository, NebulaWritableRepository, NebulaDeletableRepository {
    typealias Element = Account
    let store = AccountStore()

    func stream() -> AsyncThrowingStream<Account, any Error> {
        AsyncThrowingStream { continuation in
            Task {
                let all = await store.all()
                for account in all { continuation.yield(account) }
                continuation.finish()
            }
        }
    }

    func count() async throws -> Int { await store.all().count }
    func find(id: Account.ID) async throws -> Account? { await store.find(id) }
    func save(_ entity: Account) async throws { await store.save(entity) }
    func delete(_ id: Account.ID) async throws { await store.delete(id) }
}

@Suite("NebulaRepository capabilities")
struct NebulaRepositoryCapabilityTests {
    @Test func saveFindRoundTrip() async throws {
        let repo = AccountRepository()
        let id = Account.ID()
        let account = Account(id: id, balance: 100)
        try await repo.save(account)
        let found = try await repo.find(id: id)
        #expect(found?.id == id)
        #expect(found?.balance == 100)
    }

    @Test func findReturnsNilForAbsent() async throws {
        let repo = AccountRepository()
        let found = try await repo.find(id: Account.ID())
        #expect(found == nil)
    }

    @Test func saveIsAddOrReplace() async throws {
        let repo = AccountRepository()
        let id = Account.ID()
        try await repo.save(Account(id: id, balance: 100))
        try await repo.save(Account(id: id, balance: 250)) // replace
        let found = try await repo.find(id: id)
        #expect(found?.balance == 250)
        let count = try await repo.count()
        #expect(count == 1) // not duplicated
    }

    @Test func streamYieldsAllElements() async throws {
        let repo = AccountRepository()
        try await repo.save(Account(id: .init(), balance: 1))
        try await repo.save(Account(id: .init(), balance: 2))
        var collected: [Decimal] = []
        for try await account in repo.stream() {
            collected.append(account.balance)
        }
        #expect(collected.count == 2)
        #expect(Set(collected) == [1, 2])
    }

    @Test func deleteRemovesEntity() async throws {
        let repo = AccountRepository()
        let id = Account.ID()
        try await repo.save(Account(id: id, balance: 5))
        try await repo.delete(id)
        let found = try await repo.find(id: id)
        #expect(found == nil)
    }

    @Test func deleteAbsentIsNoOp() async throws {
        let repo = AccountRepository()
        // Deleting an absent id must not throw (the protocol leaves this to the
        // concrete repo; this one treats it as a no-op).
        try await repo.delete(Account.ID())
        #expect(try await repo.count() == 0)
    }
}

@Suite("NebulaRepository existentials")
struct NebulaRepositoryExistentialTests {
    @Test func anyRepositoryIsSendable() {
        // `any NebulaRepository<Account>` is Sendable when Element: Sendable
        // (compiler-verified — no @unchecked).
        func consume<T: Sendable>(_ v: T) {}
        let r: any NebulaRepository<Account> = AccountRepository()
        consume(r)
    }

    @Test func existentialRoutesToConcrete() async throws {
        let repo = AccountRepository()
        let id = Account.ID()
        try await repo.save(Account(id: id, balance: 7))
        // A keyed existential exposes find(id:) (NebulaKeyedRepository refines
        // read-only, NOT writable — save stays on the concrete type / the
        // writable existential).
        let keyed: any NebulaKeyedRepository<Account> = repo
        let found = try await keyed.find(id: id)
        #expect(found?.balance == 7)
    }
}
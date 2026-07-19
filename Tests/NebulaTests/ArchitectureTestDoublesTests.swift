//
//  ArchitectureTestDoublesTests.swift
//  NebulaTests
//
//  Wave H3 — Clean Architecture toolkit test-double tests (Swift Testing):
//  NebulaFakeRepository (keyed/writable/deletable in-memory store),
//  NebulaStubUseCase (fixed Result output, execute + executeTyped),
//  NebulaSpyUseCase (records inputs, delegates to body; introduces
//  `await confirmation(expectedCount:)` — the spy's body fires the
//  confirmation per invocation). Sendable derivation checked.
//

import Testing
import Foundation
import Synchronization
import Nebula

// MARK: - Fixtures

private struct Account: NebulaEntity, Equatable {
    typealias ID = NebulaID<Account>
    let id: ID
    var balance: Int
}

private struct Echo: Sendable, Equatable {
    let value: Int
}

// `ErrorCapture` is reused from ErrorTests.swift (internal, same module).

// MARK: - NebulaFakeRepository

@Suite("NebulaFakeRepository")
struct NebulaFakeRepositoryTests {
    @Test func saveFindRoundTrip() async throws {
        let repo = NebulaFakeRepository<Account>()
        let id = Account.ID()
        try await repo.save(Account(id: id, balance: 100))
        let found = try await repo.find(id: id)
        #expect(found == Account(id: id, balance: 100))
    }

    @Test func findReturnsNilForAbsent() async throws {
        let repo = NebulaFakeRepository<Account>()
        #expect(try await repo.find(id: Account.ID()) == nil)
    }

    @Test func saveIsAddOrReplace() async throws {
        let repo = NebulaFakeRepository<Account>()
        let id = Account.ID()
        try await repo.save(Account(id: id, balance: 1))
        try await repo.save(Account(id: id, balance: 2))
        #expect(try await repo.find(id: id)?.balance == 2)
        #expect(try await repo.count() == 1)
    }

    @Test func streamYieldsAllElements() async throws {
        let repo = NebulaFakeRepository<Account>()
        try await repo.save(Account(id: .init(), balance: 10))
        try await repo.save(Account(id: .init(), balance: 20))
        var balances: [Int] = []
        for try await account in repo.stream() { balances.append(account.balance) }
        #expect(balances.count == 2)
        #expect(Set(balances) == [10, 20])
    }

    @Test func deleteRemovesEntity() async throws {
        let repo = NebulaFakeRepository<Account>()
        let id = Account.ID()
        try await repo.save(Account(id: id, balance: 5))
        try await repo.delete(id)
        #expect(try await repo.find(id: id) == nil)
    }

    @Test func deleteAbsentIsNoOp() async throws {
        let repo = NebulaFakeRepository<Account>()
        try await repo.delete(Account.ID())
        #expect(try await repo.count() == 0)
    }

    @Test func conformsToCapabilityExistentials() async throws {
        // The fake is simultaneously keyed, writable, and deletable.
        let repo = NebulaFakeRepository<Account>()
        let id = Account.ID()
        let writable: any NebulaWritableRepository<Account> = repo
        try await writable.save(Account(id: id, balance: 7))
        let keyed: any NebulaKeyedRepository<Account> = repo
        #expect(try await keyed.find(id: id)?.balance == 7)
        let deletable: any NebulaDeletableRepository<Account> = repo
        try await deletable.delete(id)
        #expect(try await keyed.find(id: id) == nil)
    }

    @Test func isSendable() {
        // Sendable is derived (final class, single immutable `let Mutex`) — no
        // @unchecked. Required so the fake can cross task/actor boundaries.
        func consume<T: Sendable>(_ v: T) {}
        consume(NebulaFakeRepository<Account>())
    }
}

// MARK: - NebulaStubUseCase

@Suite("NebulaStubUseCase")
struct NebulaStubUseCaseTests {
    @Test func successReturnsFixedValue() async throws {
        let stub = NebulaStubUseCase<Echo, Int>(output: .success(42))
        let out = try await stub.execute(Echo(value: 1))
        #expect(out == 42)
    }

    @Test func failureThrowsNebulaError() async {
        let error = NebulaError(code: .init(domain: "D", code: 1), kind: .validation, message: "nope")
        let stub = NebulaStubUseCase<Echo, Int>(output: .failure(error))
        await #expect(throws: NebulaError.self) {
            try await stub.execute(Echo(value: 1))
        }
    }

    @Test func executeTypedThrowsStoredNebulaError() async {
        let error = NebulaError(code: .init(domain: "D", code: 2), kind: .validation, message: "typed")
        let stub = NebulaStubUseCase<Echo, Int>(output: .failure(error))
        await #expect(throws: NebulaError.self) {
            try await stub.executeTyped(Echo(value: 1))
        }
    }

    @Test func executeTypedReturnsSuccess() async throws {
        let stub = NebulaStubUseCase<Echo, Int>(output: .success(9))
        let out = try await stub.executeTyped(Echo(value: 1))
        #expect(out == 9)
    }

    @Test func isSendable() {
        func consume<T: Sendable>(_ v: T) {}
        consume(NebulaStubUseCase<Echo, Int>(output: .success(1)))
    }
}

// MARK: - NebulaSpyUseCase

@Suite("NebulaSpyUseCase")
struct NebulaSpyUseCaseTests {
    @Test func recordsInputsAndDelegatesToBody() async throws {
        let spy = NebulaSpyUseCase<Echo, Int> { $0.value * 2 }
        let out = try await spy.execute(Echo(value: 21))
        #expect(out == 42)
        #expect(spy.callCount == 1)
        #expect(spy.inputs() == [Echo(value: 21)])
    }

    @Test func bodyFiresOncePerInvocationViaConfirmation() async throws {
        // The spy's body fires the confirmation per invocation — the new
        // `confirmation(expectedCount:)` pattern in this suite.
        try await confirmation(expectedCount: 3) { confirm in
            let spy = NebulaSpyUseCase<Echo, Int> { input in
                confirm()
                return input.value
            }
            _ = try await spy.execute(Echo(value: 1))
            _ = try await spy.execute(Echo(value: 2))
            _ = try await spy.execute(Echo(value: 3))
            #expect(spy.callCount == 3)
            #expect(spy.inputs().map(\.value) == [1, 2, 3])
        }
    }

    @Test func callCountStartsAtZero() {
        let spy = NebulaSpyUseCase<Echo, Int> { $0.value }
        #expect(spy.callCount == 0)
        #expect(spy.inputs().isEmpty)
    }

    @Test func bodyMayThrowAndSpyRethrows() async {
        struct Boom: Error, Equatable {}
        let spy = NebulaSpyUseCase<Echo, Int> { _ in throw Boom() }
        await #expect(throws: Boom.self) {
            try await spy.execute(Echo(value: 1))
        }
        // The input is recorded BEFORE the body runs.
        #expect(spy.callCount == 1)
    }

    @Test func isSendable() {
        // A spy is shared across tasks in `confirmation` — it must be Sendable.
        // Derived (final class, all-`let` Sendable properties) — no @unchecked.
        func consume<T: Sendable>(_ v: T) {}
        consume(NebulaSpyUseCase<Echo, Int> { $0.value })
    }
}
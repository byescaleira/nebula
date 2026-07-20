//
//  main.swift
//  AuroraExample
//
//  Wave N3 — a runnable end-to-end demonstration of the Aurora pattern: a
//  SwiftData `@Model`, a Nebula `NebulaEntity` DTO, an `AuroraEntityMapping`
//  bridging them, an in-memory `ModelContainer`, and an `AuroraRepository`
//  round-tripping `save` / `find` / `stream` / `count` / `delete`. Compiling +
//  running this is the N3 gate. Not a shipped product — living docs.
//

import Foundation
import SwiftData
import Nebula
import Aurora

// MARK: - Persistence (`@Model` — non-Sendable, lives behind the @ModelActor)

@Model
final class AccountRecord {
    @Attribute(.unique) var uid: UUID
    var balance: Decimal
    init(uid: UUID, balance: Decimal) {
        self.uid = uid
        self.balance = balance
    }
}

// MARK: - Domain (Sendable NebulaEntity DTO — crosses the boundary)

struct Account: NebulaEntity {
    typealias ID = NebulaID<Account>
    let id: ID
    var balance: Decimal
}

// MARK: - Mapping (type-level bridge)

enum AccountMapping: AuroraEntityMapping, Sendable {
    typealias Model = AccountRecord
    typealias Entity = Account

    static func toEntity(_ model: AccountRecord) -> Account {
        Account(id: Account.ID(rawValue: model.uid), balance: model.balance)
    }

    static func insert(_ entity: Account, in context: ModelContext) -> AccountRecord {
        let record = AccountRecord(uid: entity.id.rawValue, balance: entity.balance)
        context.insert(record)
        return record
    }

    static func update(_ model: AccountRecord, from entity: Account) {
        // Identity (uid) is immutable; only mutable state is written.
        model.balance = entity.balance
    }

    static func descriptor(for id: Account.ID) -> FetchDescriptor<AccountRecord> {
        let raw = id.rawValue
        return FetchDescriptor(predicate: #Predicate { $0.uid == raw })
    }

    static func descriptor() -> FetchDescriptor<AccountRecord> {
        FetchDescriptor()
    }
}

// MARK: - Round-trip

@discardableResult
func run() async throws -> Bool {
    let container = try ModelContainer(
        for: AccountRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let repo = AuroraRepository<AccountMapping>(modelContainer: container)

    let alice = Account(id: .init(), balance: 100)
    let bob = Account(id: .init(), balance: 250)

    try await repo.save(alice)
    try await repo.save(bob)
    print("count after two saves: \(try await repo.count())")        // 2

    let fetched = try await repo.find(id: alice.id)
    print("find(alice.id).balance: \(fetched?.balance ?? -1)")       // 100

    // Add-or-replace: saving alice with a new balance updates the existing record.
    try await repo.save(Account(id: alice.id, balance: 100))
    print("count after upsert: \(try await repo.count())")           // 2 (no duplicate)

    var seen: [Decimal] = []
    for try await account in repo.stream() { seen.append(account.balance) }
    print("streamed balances: \(seen.sorted())")                     // [100, 250]

    try await repo.delete(bob.id)
    print("count after delete: \(try await repo.count())")           // 1
    return true
}

try await run()
//
//  ArchitectureDomainTests.swift
//  NebulaTests
//
//  Wave H1 — Clean Architecture toolkit domain layer tests (Swift Testing):
//  NebulaValue marker, NebulaEntity (Sendable + Identifiable), NebulaAggregate
//  refinement, and the NebulaID phantom identity (equatable/hashable,
//  Identifiable, CustomStringConvertible, phantom type protection).
//

import Testing
import Foundation
import Nebula

// MARK: - Fixtures

private struct Money: NebulaValue {
    let amount: Decimal
    let currency: String
}

private struct Account: NebulaEntity {
    typealias ID = NebulaID<Account>
    let id: ID
    var balance: Decimal
}

private struct Order: NebulaAggregate {
    typealias ID = NebulaID<Order>
    let id: ID
    var lines: [String]
}

@Suite("NebulaValue")
struct NebulaValueTests {
    @Test func conformsAndIsEquatableHashable() {
        let a = Money(amount: 10, currency: "USD")
        let b = Money(amount: 10, currency: "USD")
        let c = Money(amount: 11, currency: "USD")
        #expect(a == b)
        #expect(a != c)
        // Hashable (usable as a Set/Dictionary key).
        #expect(Set([a, b]).count == 1)
    }

    @Test func isSendable() {
        func consume<T: Sendable>(_ v: T) {}
        consume(Money(amount: 1, currency: "USD"))
    }
}

@Suite("NebulaEntity")
struct NebulaEntityTests {
    @Test func identifiableAndSendable() {
        let acc = Account(id: .init(), balance: 5)
        // The entity's id is its NebulaID phantom (a compile-time typed
        // assignment — `acc.id` is `NebulaID<Account>`).
        let id: NebulaID<Account> = acc.id
        #expect(id.rawValue == acc.id.rawValue)
        func consume<T: Sendable>(_ v: T) {}
        consume(acc)
    }

    @Test func aggregateRefinesEntity() {
        // NebulaAggregate is a NebulaEntity (the marker adds no requirements).
        func accept<E: NebulaEntity>(_ e: E) {}
        let order = Order(id: .init(), lines: ["a"])
        accept(order)
    }
}

@Suite("NebulaID")
struct NebulaIDTests {
    @Test func rawValueRoundTripsAndIsRandom() {
        let a = Account.ID()
        let b = Account.ID(rawValue: a.rawValue)
        #expect(a == b)
        #expect(a.rawValue == b.rawValue)
        // Two random IDs are (overwhelmingly) distinct.
        #expect(Account.ID() != Account.ID())
    }

    @Test func isIdentifiableToItself() {
        let id = Account.ID()
        // `Identifiable.id` returns `self`.
        #expect(id.id == id)
    }

    @Test func equatableAndHashable() {
        let raw = UUID()
        let a = Account.ID(rawValue: raw)
        let b = Account.ID(rawValue: raw)
        #expect(a == b)
        #expect(Set([a, b]).count == 1)
        let other = Account.ID()
        #expect(a != other)
    }

    @Test func descriptionIsUUIDString() {
        let raw = UUID()
        let id = Account.ID(rawValue: raw)
        #expect(id.description == raw.uuidString)
    }

    @Test func isSendableAndIsNebulaValue() {
        func consumeValue<T: NebulaValue>(_ v: T) {}
        func consumeSendable<T: Sendable>(_ v: T) {}
        let id = Account.ID()
        consumeValue(id)
        consumeSendable(id)
    }

    @Test func phantomTypesAreDistinct() {
        // A `NebulaID<Account>` and a `NebulaID<Order>` are distinct types —
        // a compile-time guarantee (phantom). The typed assignments below
        // compile only because each ID carries its own phantom; the line
        // `let mixed: NebulaID<Order> = accountId` would not compile.
        let accountId = Account.ID()
        let orderId = Order.ID()
        let a: NebulaID<Account> = accountId
        let o: NebulaID<Order> = orderId
        #expect(a.rawValue == accountId.rawValue)
        #expect(o.rawValue == orderId.rawValue)
    }
}
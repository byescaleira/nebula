# ``Aurora``

> The persistence-architecture sibling of Nebula: a `@ModelActor`-backed SwiftData
> repository adapter that conforms to Nebula's Foundation-only `NebulaRepository`
> ports, plus the `@Model`↔Sendable entity mapping that bridges SwiftData's
> non-`Sendable` `@Model`/`ModelContext` to Nebula's `Sendable` ``NebulaEntity``
> DTOs.

## Overview

Nebula is Foundation-only — no SwiftUI, no SwiftData. It ships the
**seams**: the async `NebulaRepository` capability ports (read-only / keyed /
writable / deletable). Aurora ships the **concrete SwiftData adapter** that
conforms to those ports, so an app gets a ready persistence layer without
Nebula itself importing SwiftData.

Aurora is a **separate local SwiftPM package** depending on Nebula via a local
path (`../`). The separation is load-bearing: `import Aurora` from inside Nebula
is a hard compile error (Nebula declares no such dependency), so the Clean
Architecture dependency rule — domain and use cases never import persistence —
is **compiler-enforced across packages**. This mirrors the Meridian (presentation)
sibling and resolves the SwiftData placement decision (sibling package, not a
gated Nebula helper).

### The concurrency model

SwiftData's `@Model` classes and `ModelContext` are **not** `Sendable` (verified
against the Xcode 27 Beta 3 SDK). The `@ModelActor` macro gives
``AuroraRepository`` an actor-isolated `ModelContext`, and the
``AuroraEntityMapping`` bridges the non-`Sendable` `@Model` to the `Sendable`
``NebulaEntity`` DTO that crosses the boundary. Nothing non-`Sendable` escapes
the actor.

### The mapping

``AuroraEntityMapping`` is a **type-level** protocol (static methods) so the
repository holds no per-instance mapping state — only the `@ModelActor`-
synthesized `ModelContext`. The app conforms it per `@Model` type, declaring how
to convert in both directions and how to build the `FetchDescriptor`s:

```swift
@Model
final class AccountRecord {
    @Attribute(.unique) var uid: UUID
    var balance: Decimal
    init(uid: UUID, balance: Decimal) { self.uid = uid; self.balance = balance }
}

struct Account: NebulaEntity {
    typealias ID = NebulaID<Account>
    let id: ID
    var balance: Decimal
}

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
```

### The repository

```swift
let container = try ModelContainer(
    for: AccountRecord.self,
    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
)
let repo = AuroraRepository<AccountMapping>(modelContainer: container)

let account = Account(id: .init(), balance: 100)
try await repo.save(account)          // insert (add-or-replace by id)
try await repo.find(id: account.id)   // → account
try await repo.count()                // → 1
for try await a in repo.stream() { }  // → [account]
try await repo.delete(account.id)
```

`stream()` is synchronous (the port returns an `AsyncThrowingStream`, not
`async`), so it is `nonisolated` and spawns a `Task` that hops to the actor to
fetch. `count()` / `find(id:)` / `save(_:)` / `delete(_:)` are `async` and run on
the actor. SwiftData errors are rethrown untyped (Nebula's public-API posture);
an app that wants ``NebulaRepositoryError`` wraps at the use-case boundary.

## Topics

### Mapping
- ``AuroraEntityMapping``

### Repository
- ``AuroraRepository``
- ``AuroraRepository/stream()``
- ``AuroraRepository/count()``
- ``AuroraRepository/find(id:)``
- ``AuroraRepository/save(_:)``
- ``AuroraRepository/delete(_:)``
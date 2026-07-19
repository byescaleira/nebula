# Domain — Entities & Values

The innermost Clean Architecture layer: the markers and the phantom-typed identity value.

## Overview

Entities carry enterprise business rules and a stable identity; values are the simple, immutable data structures that cross layer boundaries. Nebula ships markers and an identity value — **not** concrete entities. The app's `Domain` module (recommended) defines its entities against these markers.

- ``NebulaValue`` — a `Sendable`, `Equatable`, `Hashable` marker for simple immutable values.
- ``NebulaEntity`` — a `Sendable`, `Identifiable` marker for entities; `ID: Sendable, Hashable`. Deliberately **not** `Equatable` (entity equality is the entity's own decision).
- ``NebulaAggregate`` — a marker for an aggregate root (a boundary that is semantic, not compiled).
- ``NebulaID`` — a phantom-typed identity value backed by `UUID`. A `NebulaID<Account>` and a `NebulaID<Order>` are distinct types even though both wrap a `UUID`. `Sendable`/`Equatable`/`Hashable` are derived from the `UUID`; `Codable` is intentionally **not** conformed on the type so the raw encoding is the entity's decision.

```swift
struct Account: NebulaEntity {
    typealias ID = NebulaID<Account>
    let id: ID
    var balance: Decimal
}
```

For a non-UUID identity (e.g. a server-assigned `Int`), define a custom `Sendable & Hashable` `ID` type — ``NebulaEntity`` only constrains `ID` to `Sendable, Hashable`.

## Topics

### Markers
- ``NebulaValue``
- ``NebulaEntity``
- ``NebulaAggregate``

### Identity
- ``NebulaID``
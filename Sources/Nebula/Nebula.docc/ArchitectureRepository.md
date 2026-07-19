# Repositories

The repository capability protocols (Fowler's Repository) and the repository-layer error.

## Overview

``NebulaRepository`` is a `Sendable` protocol with a primary associated type `Element: Sendable`, so `any NebulaRepository<Account>` is `Sendable` (compiler-verified — no `@unchecked`). Nebula ships **capabilities**, not a CRUD mandate: the base protocol declares only `Element`; the app conforms to the capabilities it needs.

- ``NebulaReadOnlyRepository`` — `stream()` / `count()`. `Element` is unconstrained so read models (projections that are not full entities) are valid. `stream()` returns the concrete `AsyncThrowingStream` (a `some AsyncSequence` return is illegal in a protocol requirement).
- ``NebulaKeyedRepository`` — adds `find(id:)` as a **protocol requirement** (not a default extension) so the app overrides it with its own indexed lookup; `Element: NebulaEntity`.
- ``NebulaWritableRepository`` — adds `save(_:)` (add-or-replace by id). Deliberately **no** `update` verb (a partial update is a use-case concern).
- ``NebulaDeletableRepository`` — adds `delete(_:)`. A separate protocol so append-only stores (audit logs, event stores) need not implement a trapping delete.

```swift
struct AccountRepository: NebulaKeyedRepository, NebulaWritableRepository, NebulaDeletableRepository {
    typealias Element = Account
    // …stream(), count(), find(id:), save(_:), delete(_:)
}
```

### Repository error

``NebulaRepositoryError`` is the repository-layer ``NebulaFailure``: an open struct with a ``NebulaRepositoryError/Source`` (`.local`/`.remote`/`.unknown`), an open ``NebulaRepositoryError/Kind`` (presets: `.notFound`, `.alreadyExists`, `.storeFailure`, `.mapping`, `.constraintViolation`, `.cancelled`, `.unknown`), and factory statics. Its `coarseKind` maps into ``NebulaError/Kind`` (constraintViolation→`.validation`, mapping→`.decoding`, remote→`.network`, else `.unknown`).

## Topics

### Capability protocols
- ``NebulaRepository``
- ``NebulaReadOnlyRepository``
- ``NebulaKeyedRepository``
- ``NebulaWritableRepository``
- ``NebulaDeletableRepository``

### Repository error
- ``NebulaRepositoryError``
- ``NebulaRepositoryError/Source``
- ``NebulaRepositoryError/Kind``
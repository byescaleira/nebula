# Test Doubles

In-target test doubles for the Clean Architecture seams: a fake repository, a stub use case, and a spy use case.

## Overview

Nebula ships its test doubles in the main target (decision #8 — the documented test-helper exception, mirroring ``NebulaMemoryLogHandler``) so a test target can depend on Nebula without re-rolling doubles. Inject them by **explicit parameter** — never resolve them from ``NebulaRegistryConfig``.

- ``NebulaFakeRepository`` — an in-memory fake conforming to the keyed / writable / deletable capabilities. A `final class` with a `let Mutex<[Entity.ID: Entity]>`. `Sendable` is **derived** — the class is `final` with a single immutable `let` property of a `Sendable` type, so the compiler synthesizes `Sendable` with **no `@unchecked`** (the class-over-struct choice mirrors ``NebulaMemoryLogHandler``: a `Mutex`-typed stored property would propagate `~Copyable` to an owning *struct*, so the shared mutable container lives in a class). `save(_:)` is add-or-replace; `delete(_:)` on an absent id is a no-op; `stream()` snapshots the store.
- ``NebulaStubUseCase`` — a `Sendable` struct that returns a fixed `Result<O, NebulaError>` regardless of input. `execute(_:)` returns the value or throws the ``NebulaError``; `executeTyped(_:)` mirrors the typed-throws path. A stub records nothing.
- ``NebulaSpyUseCase`` — a `final class` that records every input it receives (``callCount``/``inputs()``), then delegates to a `body`. `Sendable` is **derived** (final class, all-`let` `Sendable` properties), so a spy can be shared across tasks. Use Swift Testing's `confirmation(expectedCount:)` to assert the body fired once per invocation.

```swift
let repo = NebulaFakeRepository<Account>()
let stub = NebulaStubUseCase<Echo, Int>(output: .success(42))
let spy = NebulaSpyUseCase<Echo, Int> { $0.value * 2 }
```

A `NebulaMockRepository` was deferred (v1 ships Fake/Stub/Spy).

## Topics

### Doubles
- ``NebulaFakeRepository``
- ``NebulaStubUseCase``
- ``NebulaSpyUseCase``
# Composition root

Where the app assembles its object graph at launch — explicit constructor injection of `Sendable` values, with ``NebulaRegistryConfig`` as the process-wide convenience.

## Overview

Nebula ships the **seams**, not the container. The composition root — the one place that knows which concrete adapter backs each port — is the **app's job**, at `@main` / `App.init`. `<doc:ArchitectureRegistry>` states the thesis: ``NebulaRegistry`` is "deliberately **not** a DI container (no scoping, graph, or lifecycle)" and "the primary, testable path is explicit-parameter constructor injection; ``NebulaRegistryConfig`` is the process-wide convenience." This article names what that one leaves implicit: how to wire the full vertical at launch.

There is no Apple DI framework. Apple ships `Mutex` / `Atomic` (Synchronization), `@MainActor`, and typed throws as **primitives, not a container** — and the composition-root-as-app-job stance is community consensus (Point-Free Dependencies, TCA, swift-navigation, Factory, InnoDI), not an Apple-published position. The closest official corroboration is WWDC19 Session 415 "Modern Swift API Design": explore concrete types first, prefer generic structs over "is-a" protocols — which validates the ``NebulaUseCase`` struct-of-closures and the ``NebulaRepository`` PAT. `dependencies: []` forbids Resolver / Factory / Swinject, so the only path consistent with the codebase is explicit-parameter constructor injection plus the registry convenience.

### Where the composition root lives

At the app's entry point only. `@MainActor` is confined to the root that owns UI (viewmodels, coordinators); services are `nonisolated Sendable` and cross the actor boundary via `await`. Nebula has **no** `@MainActor` default isolation (no SwiftUI), so the app supplies its own. A vertical that demonstrates the load-bearing `@MainActor` hop — a `@MainActor @Observable` viewmodel receiving use cases via constructor injection — lives in the sibling **Meridian** package (SwiftUI-bearing), not in Nebula. See `<doc:ArchitecturePresentation>` for the ``NebulaRouter`` / ``NebulaViewModel`` half this recipe hands off to.

### Wiring order

The canonical vertical is `viewmodel ← use case ← repository ← gateway ← cache`. At launch:

1. Build a ``NebulaRegistryConfiguration`` via `.withFactory(for:_:)`, one binding per port.
2. Publish it **once** with ``NebulaRegistryConfig/set(_:)`` (process-wide `Mutex` accessor — ergonomics path).
3. Wrap the published snapshot in a ``NebulaRegistry`` and `resolve(_:as:)` the concrete adapters.
4. Pass those adapters as **explicit parameters** into the ``NebulaUseCase`` `@Sendable` body (the testable path — tests pass fakes directly, the registry is never on the test path).
5. Decorate the use case with `.instrumented()` so logging, measurement, and error reporting route through their process-wide configs.
6. Hand the use case to the app's `@MainActor @Observable` viewmodel via constructor injection (in the sibling).

```swift
import Nebula

// 1. App-owned adapters conform to Nebula ports. Sendable values.
//    AccountRepository wraps a NebulaHTTPGateway + NebulaURLCache in
//    production, or a NebulaFakeRepository in tests.
let config = NebulaRegistryConfiguration()
    .withFactory(for: "com.acme.account.repo") { AccountRepository() }
    .withFactory(for: "com.acme.account.gateway") { NebulaHTTPGateway(/* … */) }

// 2. Publish once at launch.
NebulaRegistryConfig.set(config)

// 3. Resolve concrete adapters.
let registry = NebulaRegistry(NebulaRegistryConfig.get())
let repo = registry.resolve("com.acme.account.repo", as: AccountRepository.self)!

// 4–5. Inject explicitly; decorate with logging + measurement + reporting.
let withdraw = NebulaUseCase<WithdrawInput, Account>(name: "withdraw") { input in
    var account = try await repo.find(input.accountID)
    account.debit(input.amount)
    try await repo.save(account)
    return account
}.instrumented()

// 6. Hand `withdraw` to the app's @MainActor @Observable viewmodel via
//    constructor injection. The viewmodel lives in the sibling Meridian
//    package — Nebula stops here, Foundation-only.
```

`.instrumented()` composes `reported().measured().logged()` (outermost → innermost: `logged → measured → reported → body`), each defaulting to its process-wide config; pass an explicit value to override one concern, or call an individual decorator to opt out of the others. See `<doc:ArchitectureUseCase>`, `<doc:ArchitectureRepository>`, and `<doc:ArchitectureGateway>`.

### Why not a container

Do **not** extend ``NebulaRegistry`` toward singleton caching, scoped resolution (request / session / singleton lifetimes), or auto-injection graphs — that is a DI container, exactly the scope creep flagged in the registry's risk note, and `dependencies: []` forbids the frameworks that ship one anyway. The registry is a **factory map, nothing more**: each `resolve` re-invokes the factory afresh — a *transient* lifetime, which is the only behavior it has, and precisely why it is not a singleton cache. The composition root is the only place that knows the wiring; a `NebulaCompositionRoot` / `NebulaAppContainer` helper type is deliberately **not** shipped — a trivial one is redundant (the app writes the wiring in ~20 lines at launch), and a non-trivial one drifts toward a container. Per-scope overrides à la `withDependencies` / `.dependency()` need a single entry point (TCA's `reduce`, SwiftUI's `body`); Nebula is a library with no entry point, so a task-local `DependencyValues` would collapse to manual `withValue` — explicit injection with extra steps, and a hidden global closer to `nonisolated(unsafe)` than to the `Mutex<NebulaRegistryConfiguration>` accessor.

### The `@MainActor`-factory hazard

Keep ``NebulaRegistry`` factory closures `nonisolated @Sendable`. A `@MainActor`-isolated factory may compile, but resolving it from a `Task.detached` can trip `MainActor.assertIsolated()` at runtime — the initializer did not actually run on the main actor (Factory#322). The registry stays actor-neutral; the app does the actor hop when it hands the resolved value to its `@MainActor` viewmodel.

## Topics

### Registry
- ``NebulaRegistry``
- ``NebulaRegistryConfig``
- ``NebulaRegistryConfiguration``
- ``NebulaRegistryKey``

### Use case
- ``NebulaUseCase``
- ``NebulaUseCase/instrumented(using:measure:error:)``

### Ports & test doubles the root composes
- ``NebulaRepository``
- ``NebulaGateway``
- ``NebulaFakeRepository``
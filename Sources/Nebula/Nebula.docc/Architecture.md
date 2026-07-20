# Nebula Clean Architecture Toolkit

> The second surface of Nebula: the seams that help — and let — an app implement Clean Architecture efficiently, without Nebula owning any presentation, database, or framework code.

## Overview

Nebula is a foundation **and architecture** library. The foundation half wraps Apple primitives (logging, errors, formatting, measurement, extensions). The architecture half — this toolkit — maps Uncle Bob's Clean Architecture layers onto Swift 6 / Nebula constructs and ships **only the seams**: inner-owned marker protocols, a DTO contract, repository/gateway ports, a use-case type, a validator, a registry, test doubles, and async-flow helpers. Concrete adapters (repositories, gateways, presenters, networking) live in the app. Cosmos, the SwiftUI sibling, is the presentation layer; Nebula defines no presenter and no presentation pattern (MVVM / MVC / VIP / VIPER are explicitly out of scope).

The toolkit is pure Swift + Foundation + `Synchronization` — every symbol sits at the Nebula 26 floor (no above-floor gates). All public value types derive `Sendable` (Nebula never authors `@unchecked Sendable` on a value type). The toolkit introduces **no** `@unchecked Sendable` at all: the two `final class` test-helpers (``NebulaFakeRepository``, ``NebulaSpyUseCase``) derive `Sendable` (final class, all-`let` `Sendable` properties — `Mutex` is `Sendable` when its value is), needing no `@unchecked`.

### Layers → Nebula constructs

| Clean Architecture layer | Nebula construct |
|---|---|
| **Entities** (enterprise business rules) | ``NebulaValue``, ``NebulaEntity``, ``NebulaAggregate``, ``NebulaID`` |
| **Use Cases** (application business rules) | ``NebulaUseCase`` + ``NebulaUseCaseRole``; decorators `.logged`/`.measured`/`.reported`/`.instrumented` |
| **Interface Adapters** (ports, repositories, gateways, DTOs) | ``NebulaInputPort``, ``NebulaOutputPort``, ``NebulaDTO``, ``NebulaRepository`` capability protocols, ``NebulaGateway``, ``NebulaPreferences``, ``NebulaValidator``/``NebulaAsyncValidator``, ``NebulaRegistry`` |
| **Frameworks & Drivers** | Outside Nebula — the app provides concrete adapters (URLSession, persistence, presenters). |

### Dependency rule

Dependencies point **inward only**. The inner layers (Entities, Use Cases) know nothing of outer layers. Nebula owns the inner ports and markers; the app implements them outer. The Dependency-Inversion Principle is realized by protocol ownership: Nebula defines the port, the app supplies the adapter.

### Error taxonomy

Layer errors are **per-layer open structs** conforming to ``NebulaFailure`` — ``NebulaDomainError``, ``NebulaValidationError``, ``NebulaRepositoryError`` — each bridging to the closed ``NebulaError/Kind`` enum via a caller-picked ``NebulaFailure/toNebulaError(kind:)``. Nebula never adds cases to the closed `Kind` enum; fine-grained taxonomy lives in an open `String` `code`. Per SE-0413, public Nebula APIs use untyped `throws`; ``NebulaError`` is an opt-in concrete `Failure` (``NebulaUseCase/executeTyped(_:)`` narrows to `throws(NebulaError)`).

### Dependency injection without a framework

``NebulaRegistry`` is a lightweight `Mutex`-backed registry of port→`@Sendable` factory bindings with a generic `resolve(_:as:)` — deliberately **not** a DI container (no scoping, graph, or lifecycle). `dependencies: []` forbids Resolver/Factory/Swinject. The primary, testable path is explicit-parameter constructor injection; ``NebulaRegistryConfig`` is the process-wide convenience.

### Test doubles

Nebula ships ``NebulaFakeRepository``, ``NebulaStubUseCase``, and ``NebulaSpyUseCase`` in the main target (the documented test-helper exception) so tests depend on Nebula without re-rolling doubles. Inject them by parameter — never resolve them from ``NebulaRegistryConfig``.

## Topics

### Articles
- <doc:ArchitectureDomain>
- <doc:ArchitecturePorts>
- <doc:ArchitectureErrors>
- <doc:ArchitectureUseCase>
- <doc:ArchitectureRepository>
- <doc:ArchitectureGateway>
- <doc:ArchitectureNetwork>
- <doc:ArchitectureHTTPCache>
- <doc:ArchitectureHTTPServer>
- <doc:ArchitecturePreferences>
- <doc:ArchitectureValidation>
- <doc:ArchitectureRegistry>
- <doc:ArchitectureTesting>
- <doc:ArchitectureAsync>
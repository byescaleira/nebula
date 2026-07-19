# Registry / Dependency Injection

A lightweight, `Mutex`-backed registry of port→`@Sendable` factory bindings — dependency injection **without** a DI container.

## Overview

`dependencies: []` forbids Resolver/Factory/Swinject. Nebula's DI seam is a deliberately small registry: a map of ``NebulaRegistryKey`` to transient `@Sendable () -> Any` factories with a generic `resolve(_:as:)`. There is **no** scoping, graph resolution, or lifecycle — it is not a container. The primary, testable DI path is explicit-parameter constructor injection; the registry is the ergonomics/convenience path.

- ``NebulaRegistryKey`` — an open `Sendable` `ExpressibleByStringLiteral` struct (mirrors ``NebulaLogCategory``). Consumers invent keys via a string literal without a library release. Presets: `.repository`, `.gateway`, `.useCase`.
- ``NebulaRegistryConfiguration`` — the `Sendable` value (NOT `Equatable` — it stores `@Sendable` closures). `.withFactory(for:_:)` binds; `.make(_:)` invokes a factory afresh (factories are **transient**).
- ``NebulaRegistry`` — a `Sendable` struct wrapping a configuration snapshot for **explicit** constructor injection (`init(_:)`, `resolve(_:as:)`).
- ``NebulaRegistryConfig`` — the process-wide `Mutex` accessor (`get()`/`set(_:)`/`resolve(_:as:)`), mirroring ``NebulaErrorConfig``.

```swift
let cfg = NebulaRegistryConfiguration()
    .withFactory(for: "com.acme.account.repo") { AccountRepository() }
let registry = NebulaRegistry(cfg)
let repo = registry.resolve("com.acme.account.repo", as: AccountRepository.self)
```

## Topics

### Key
- ``NebulaRegistryKey``

### Configuration
- ``NebulaRegistryConfiguration``

### Access
- ``NebulaRegistry``
- ``NebulaRegistryConfig``
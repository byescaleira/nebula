---
tags: [padroes, architecture, di, registry, composition-root, swift6, nebula]
aliases: [NebulaRegistry, NebulaRegistryKey, NebulaRegistryConfig, NebulaCompositionRoot, nebula-registry-di, Nebula DI]
related: [[nebula-clean-architecture-toolkit]], [[nebula-usecase]], [[nebula-repository]], [[nebula-domain-error]], [[nebula-errors]], [[nebula-swift6-concurrency]], [[nebula-spm-architecture]]
status: shipped
shipped: "0.2.0"
---

# Nebula Registry / DI (Composition Root)

The wiring seam of the toolkit: a lightweight `Mutex`-backed registry of port→`@Sendable` factory bindings with a generic `resolve(_:as:)` accessor — **deliberately NOT a DI container**. `dependencies: []` (`Package.swift:28/32`) forbids Resolver/Factory/Swinject and reactive frameworks; the only DI path consistent with the existing codebase is explicit-parameter constructor injection plus this process-wide `Mutex`-backed seam mirroring `NebulaErrorConfig`. Source of truth = root docs; this note is synthesis. On conflict, the root doc wins. Part of [[nebula-clean-architecture-toolkit]].

## The binding (DECISIONS row 27, verified)

`DECISIONS.md` row 27 (2026-07-18): "Process-wide `Mutex<Nebula*Config>` accessor + explicit-parameter DI (**both**)" — "`NebulaErrorConfig.get()/set(_:)` (Mutex-backed) for ergonomics; explicit `NebulaErrorConfiguration` parameter for testability. Same pattern for log/standards/measure." `CLAUDE.md` "no third-party dependencies" + `Package.swift:28` `dependencies: []` is the framework ban. The registry is the architecture-toolkit analogue of `NebulaErrorConfig` (`Sources/Nebula/Errors/NebulaErrorConfig.swift:23` `static let current = Mutex<NebulaErrorConfiguration>(.default)`, `:26` `get()`, `:31` `set(_:)`).

## What it is — and is NOT

- **IS**: a `Mutex`-backed table of port→`@Sendable () -> Any` factory closures + a generic `resolve<T>(_ key:​as:) -> T?` accessor. Factory closures are `@Sendable`; resolved instances must be `Sendable` (ports/repos are `actor`s or `Sendable` structs). The `Mutex` is `let` (`Mutex` is `~Copyable` + `@_staticExclusiveOnly` — [[nebula-swift6-concurrency]]). `withLock` uses `sending` (SE-0430).
- **IS NOT**: a DI container. No scoping (singleton/transient/request), no resolution graph, no lifecycle, no auto-injection. Any feature creep re-introduces Resolver/Factory-shaped scope — exactly the forbidden framework category. The registry is a **factory map**, nothing more.

## Recommended surface

```swift
public struct NebulaRegistryKey: Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    // open struct (extensible taxonomy) — mirrors NebulaLogCategory (NebulaLogCategory.swift:28)
}

public struct NebulaRegistryConfiguration: Sendable {
    public var factories: [NebulaRegistryKey: @Sendable () -> Any]   // @Sendable closures; NOT Equatable → config is Sendable-only
    public init(_ factories: [NebulaRegistryKey: @Sendable () -> Any] = [:])
    public func withFactory(_ make: @escaping @Sendable () -> Any, for key: NebulaRegistryKey) -> NebulaRegistryConfiguration
}

public enum NebulaRegistryConfig {
    static let current = Mutex<NebulaRegistryConfiguration>(.default)   // let — Mutex is ~Copyable
    public static func get() -> NebulaRegistryConfiguration { current.withLock { $0 } }
    public static func set(_ c: NebulaRegistryConfiguration) { current.withLock { $0 = c } }
    public static func resolve<T>(_ key: NebulaRegistryKey, as: T.Type = T.self) -> T? {
        current.withLock { $0.factories[key]?(/*run*/) as? T }   // factory invoked outside or inside lock? see risk
    }
}
```

- `NebulaRegistryKey` is an **open struct** (`Sendable, Hashable, ExpressibleByStringLiteral`) — mirrors `NebulaLogCategory` (`Sources/Nebula/Logging/NebulaLogCategory.swift:28`, extensible-by-design `:21`). Consumers add domain keys via string literal without a library release. This is the open-struct-over-closed-enum rule applied to the key taxonomy.
- `NebulaRegistryConfiguration` is `Sendable` **only** (NOT `Equatable` — the `@Sendable` factory closures are not `Equatable`, mirroring `NebulaErrorConfiguration` at `Sources/Nebula/Errors/NebulaErrorConfiguration.swift:47`, documented `:6`/`:35`).
- `NebulaRegistryConfig` is the process-wide `Mutex` accessor — `static let current` (always `let`), `get()`/`set(_:)` via `current.withLock` (`sending`, SE-0430).

(The research dimension named this `NebulaCompositionRoot`; the canonical toolkit surface uses `NebulaRegistry`/`NebulaRegistryKey`/`NebulaRegistryConfig` for parity with the other `Nebula*Config` accessors. They are the same concept — a factory-map wiring seam at the app boundary.)

## Primary path = explicit-parameter constructor injection

The registry is the **ergonomic seam at the app boundary only**. The primary, testable path is explicit-parameter constructor injection: a use case holds its port dependencies in `let`s, injected via `init`. Tests pass fakes directly ([[nebula-test-doubles]]); the registry is never on the test path. The app's composition root populates `NebulaRegistryConfig.set(…)` once at launch and resolves concrete adapters to wire into use cases. This is exactly the "both paths" decision (row 27): Mutex accessor for ergonomics, explicit parameter for testability.

## Sendable strategy

- `NebulaRegistryKey`: derived `Sendable` (`String` rawValue). No `@unchecked`.
- `NebulaRegistryConfiguration`: derived `Sendable` — but note `[@Sendable () -> Any]` dictionary values: `@Sendable` closures are `Sendable`; `Any` is the type-erased payload slot. The config struct itself is `Sendable` (all stored fields Sendable). **NOT `Equatable`**.
- `NebulaRegistryConfig`: the `Mutex` is `let`; `Mutex` is `@unchecked Sendable` in the stdlib (canonical Apple-sanctioned `@unchecked` — [[nebula-swift6-concurrency]]). **No `@unchecked` authored on a Nebula-defined type** — the `@unchecked` lives on the stdlib `Mutex`, not on `NebulaRegistryConfig`.
- Resolved instances must be `Sendable` (the `as? T` cast cannot enforce it; document that factories must return `Sendable` values — ports/repos are `actor`s or `Sendable` structs).

## Risks (see [[clean-architecture-toolkit-risks]])

- **Scope creep into a DI container** — the single biggest risk. Scoping/resolution graphs/lifecycle/auto-injection would re-introduce the forbidden framework category. Mitigation: keep it to factory bindings only; document the boundary loudly; resist any "just add singleton scope" request.
- **`@Sendable () -> Any` + `as? T` is a code smell** — a dynamic dispatch edge the Swift 6 strict-concurrency checker tolerates but cannot type-prove. `Sendable` PAT protocols (`NebulaRepository`, `NebulaUseCase`-style ports) resist `any Port` storage, so a type-erased registry needs the `Any` slot. Mitigation: the registry is optional and app-boundary-only; most wiring is explicit-parameter constructor injection (typed, no erasure).
- **Factory invocation inside vs outside the lock** — running a factory inside `current.withLock` serializes construction under the lock and risks re-entrancy if a factory itself resolves another key. Prefer: snapshot the factory under the lock, invoke it outside. Document.
- **`~Copyable` propagation** — `NebulaRegistryConfig.current` is a `Mutex` (`~Copyable`); it must be a `let` static, never copied. The accessor enum shape (`NebulaErrorConfig` precedent) keeps it as a standalone `let` global — does not propagate `~Copyable` to a `Copyable` owning type.
- **Process-wide default misleading for multi-instance types** — gateways are inherently multi-instance (different endpoints); a global `NebulaGatewayConfig` may mislead. The registry is less affected (factories are invoked per-resolve), but document that the registry is a *factory* map, not a singleton cache.

## Open questions (see [[clean-architecture-open-questions]])

- DI scope: should the registry hold **factories** (invoke per-resolve → transient) or **instances** (resolve returns the same `Sendable` → singleton)? Lean: factories only (transient by default); a caller wanting singleton caches the resolved instance itself. This keeps the registry out of lifecycle management.
- Should `NebulaRegistry` exist at all, or is `NebulaRepository`/`NebulaGateway` + explicit constructor injection enough with the app wiring its own composition root? Lean: ship the registry as an opt-in helper; the protocols + DTO marker are the load-bearing part.
- `NebulaRegistryKey` open struct vs a `@retroactive`-free keyed-by-type approach (`ObjectIdentifier(T.self)`)? Open struct keeps it string-literal-ergonomic and Sendable without `@retroactive` concerns.
- Should the registry be a single global (`NebulaRegistryConfig`) or accept an explicit `NebulaRegistryConfiguration` parameter (the "both paths" pattern)? Lean: both — `get()`/`set(_:)` for ergonomics, explicit param for tests, mirroring row 27.

## Sources

- `DECISIONS.md` row 27 (Process-wide `Mutex<Nebula*Config>` accessor + explicit-parameter DI — both).
- `CLAUDE.md` "no third-party dependencies"; `Package.swift:28/32` `dependencies: []`.
- `Sources/Nebula/Errors/NebulaErrorConfig.swift:23/26/31` (the `Mutex` accessor pattern to mirror).
- `Sources/Nebula/Errors/NebulaErrorConfiguration.swift:6/35/47` (Sendable-only-NOT-Equatable precedent for a config holding `@Sendable` closures).
- `Sources/Nebula/Logging/NebulaLogCategory.swift:21/28` (open-struct precedent for `NebulaRegistryKey`).
- Sibling notes: [[nebula-errors]] (`NebulaErrorConfig`), [[nebula-swift6-concurrency]] (`Mutex` `let`/`sending`/`~Copyable`), [[nebula-clean-architecture-toolkit]] (DI section), [[nebula-test-doubles]] (fakes via explicit injection).

Source of truth = root docs (CLAUDE.md, ARCHITECTURE.md, DECISIONS.md, VERSIONING.md); this note is the synthesis. On conflict, the root doc wins.
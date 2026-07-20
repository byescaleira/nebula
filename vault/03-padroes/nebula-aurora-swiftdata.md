---
tags: [padroes, architecture, swiftdata, persistence, concurrency, nebula, aurora]
aliases: [Aurora, AuroraRepository, AuroraEntityMapping, Nebula SwiftData, @ModelActor adapter]
related: [[nebula-data-network-architecture]], [[data-network-open-questions]], [[nebula-repository]], [[nebula-meridian-router]]
status: shipped
shipped: "2026-07-19 (Wave N3)"
---

# Aurora — SwiftData sibling package (Wave N3 — shipped)

The SwiftData half of the data+network surface ([[nebula-data-network-architecture]] Q1=(c)). A separate local SwiftPM package `Aurora/` (path-dep on Nebula, mirroring [[nebula-meridian-router]] / Meridian) that ships a `@ModelActor`-backed repository adapter conforming to Nebula's Foundation-only `NebulaRepository` ports, plus the `@Model`↔Sendable entity mapping. Source of truth = `Aurora/Sources/Aurora/AuroraEntityMapping.swift` + `AuroraRepository.swift` + `Aurora/Package.swift`; this note is synthesis.

## What shipped (Wave N3)

| Symbol | Path | Role |
|---|---|---|
| `AuroraEntityMapping` | `Aurora/Sources/Aurora/AuroraEntityMapping.swift` | A **type-level** protocol (static methods) bridging a SwiftData `@Model` (`PersistentModel`) to a Nebula ``NebulaEntity`` DTO. The app conforms it per `@Model` type: `toEntity` / `insert(_:in:)` / `update(_:from:)` / `descriptor(for:)` / `descriptor()`. Type-level so the repository holds no per-instance mapping state. |
| `AuroraRepository<Mapping>` | `Aurora/Sources/Aurora/AuroraRepository.swift` | A `@ModelActor` `actor` generic over `Mapping: AuroraEntityMapping & Sendable`, conforming to `NebulaRepository` + `NebulaReadOnlyRepository` + `NebulaKeyedRepository` + `NebulaWritableRepository` + `NebulaDeletableRepository`. `Element = Mapping.Entity`. `@ModelActor` synthesizes the `ModelContext` isolation + `init(modelContainer:)`. |
| `AuroraExample` | `Aurora/Sources/AuroraExample/main.swift` | Runnable end-to-end demo: `@Model` `AccountRecord` + `Account: NebulaEntity` + `AccountMapping` + in-memory `ModelContainer` + `AuroraRepository` CRUD round-trip. `swift run AuroraExample` (gate). Not a shipped product. |

Tests: `AuroraTests/AuroraRepositoryTests.swift` (12) — save (insert + add-or-replace by id), find (present/absent), count, stream (all/empty), delete (present/absent-no-op), port-conformance (assign-to-existential + cast-back proof for all four capability ports), Sendable-across-`Task`. 12 tests / 3 suites green; zero concurrency warnings; release clean.

## Design decisions

- **Sibling package, not a gated Nebula helper (Q1 = (c)).** `import Aurora` from Nebula is a **hard compile error** (verified: `swiftc -I <nebula-build> ... 'import Aurora'` → "no such module 'Aurora'") — Nebula's manifest is `dependencies: []` with no target depending on Aurora, so the Clean Architecture dependency rule (domain/use-cases never import persistence) is compiler-enforced across packages. Mirrors Meridian (presentation) exactly. Resolves the SwiftData placement risk: SwiftData is heavyweight, `ModelContext`/`@Model` are non-Sendable, and the `@ModelActor` form wants its own module graph — grafting it into Foundation-only Nebula re-creates the Meridian tension that splitting packages already resolved.
- **`@ModelActor`, not a plain actor + stored `ModelContext`.** `@ModelActor` is Apple's blessed SwiftData concurrency pattern: it synthesizes an actor-isolated `ModelContext` (via a `ModelExecutor`) and `init(modelContainer:)`. A plain actor storing `ModelContext` would need manual isolation of a non-Sendable type. Verified `@ModelActor` composes with a **generic** actor (`actor AuroraRepository<Mapping: ...>`) and with protocol conformances — the macro generates the `ModelActor` machinery and the generic param + conformances layer on top.
- **The mapping is type-level (static methods), not an instance.** `AuroraEntityMapping` declares `static func`s, so `AuroraRepository` holds no per-instance mapping state — only the `@ModelActor`-synthesized `ModelContext`. This sidesteps the custom-init problem (the macro's `init(modelContainer:)` is the only init; no need to thread a mapping instance through it). The app conforms with a caseless `enum` (a namespace) — `enum AccountMapping: AuroraEntityMapping, Sendable`.
- **`Mapping: Sendable` is required.** Without it, the `nonisolated stream()` → actor hop captures a non-Sendable `Mapping.Type` metatype and triggers the SE-0470 "isolated conformance" warning ("conformance of 'Mapping' may be isolated"). A caseless `enum` derives `Sendable` trivially; the constraint makes the metatype Sendable and the warning disappears. (CLAUDE.md: keep conformances nonisolated; don't rely on SE-0470.)
- **`stream()` is `nonisolated` + spawns a `Task`.** The port's `stream() -> AsyncThrowingStream<Element, any Error>` is **synchronous** (not `async`), so the conforming actor method must be `nonisolated` (an isolated method couldn't be called synchronously from outside). It returns an `AsyncThrowingStream` whose build closure spawns a `Task` that hops to the actor (`await self.streamAll(into:)`) to fetch + map + yield. Cancellation finishes the stream. `count()`/`find(id:)`/`save(_:)`/`delete(_:)` are `async` and run on the actor directly.
- **`delete(_:)` takes an ID, not the entity** (the port contract — `NebulaDeletableRepository.delete(_ id: Element.ID)`). The adapter fetches the `@Model` by id via `Mapping.descriptor(for:)` and deletes it; an absent id is a no-op (matches the port).
- **SwiftData errors are rethrown untyped.** Aurora mirrors Nebula's public-API posture (untyped `throws` for evolution safety). An app that wants ``NebulaRepositoryError`` wraps at the use-case boundary. No new `NebulaError.Kind` case (closed-enum rule); Aurora doesn't touch Nebula's error mapping.
- **`@Model`↔DTO identity bridge.** The `@Model` stores the entity's `NebulaID` raw `UUID` as a field (`@Attribute(.unique) var uid: UUID`); `descriptor(for:)` builds a `#Predicate { $0.uid == raw }`. The mapping owns the identity-field shape; the adapter is identity-agnostic.

## TDD fit (Wave N3)

- Every test builds a fresh in-memory `ModelContainer` (`ModelConfiguration(isStoredInMemoryOnly: true)`) — no on-disk state, no cross-test pollution.
- Port-conformance tests assign the concrete `AuroraRepository` to each `any Nebula…Repository` existential (compile-time conformance proof) and cast back (`as? AuroraRepository<NoteMapping>`) for a runtime proof. Methods are asserted through the **concrete** type because Swift 6.2 disallows calling `associatedtype`-returning methods (`stream()`, `save(_:)`, `find(id:)`) on `any Nebula…Repository` existentials (opaque `Element`) — documented inline.
- The Sendable test captures the repository in a child `Task` (the whole point of `Sendable`).

## Notes / guardrails

- SwiftData is a system framework (not an SPM dep) → Aurora stays third-party-free (`dependencies` lists only the local Nebula sibling).
- Versioning: **Aurora N ↔ Nebula N ↔ OS N** lockstep (mirrors Meridian N ↔ Nebula N ↔ OS N). Policy finalized in `VERSIONING.md` at N4.
- The v0.4 surface is lean: one mapping protocol + one repository adapter. No `@Query` helper, no `ModelContainer` factory beyond `init(modelContainer:)`, no schema migration tooling, no relationship-walking convenience. Those wait for a use.
- Promoting Aurora to its own git repo (path dep → git URL) is a documented future step, same as Meridian.

## Build gate (Wave N3)

- Aurora: `swift build && swift test && swift build -c release` → 12 tests / 3 suites, zero warnings, release clean. `swift run AuroraExample` prints the CRUD round-trip (count 2 → find 100 → upsert count 2 → stream [100,250] → delete count 1).
- Binding rule: `import Aurora` from the Nebula context → "no such module 'Aurora'" (hard compile error) — verified. Per-platform `xcodebuild` pass deferred to N4 (SwiftData + Foundation only; no `#if os()` in Aurora source).
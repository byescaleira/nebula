---
tags: [padroes, architecture, repository, gateway, cqrs, swift6, nebula]
aliases: [NebulaRepository, Nebula Gateway, NebulaReadOnlyRepository, NebulaRepositoryError, nebula-repository]
related: [[nebula-clean-architecture-toolkit]], [[nebula-usecase]], [[nebula-domain-error]], [[nebula-validation-invariants]], [[nebula-test-doubles]], [[nebula-errors]], [[nebula-codable-foundation]], [[nebula-swift6-concurrency]]
status: shipped
shipped: "0.2.0"
---

# Nebula Repository & Gateway

The Interface-Adapter data seams: `NebulaRepository<Element>` + CQRS capability sub-protocols (Fowler [Repository](https://martinfowler.com/eaaCatalog/repository.html)), `NebulaGateway` (Fowler [Gateway](https://martinfowler.com/eaaCatalog/gateway.html)), the open-struct `NebulaRepositoryError`, and a 5th config pair for gateways. Source of truth = root docs; this note is synthesis. On conflict, the root doc wins. Part of [[nebula-clean-architecture-toolkit]].

## Fowler, verbatim (verified)

- **Repository** — "Mediates between the domain and data mapping layers using a collection-like interface for accessing domain objects." Supports "a clean separation and one-way dependency between the domain and data mapping layers." Objects can be added/removed; **no `update` verb** (mutated aggregates are saved back through add/save); **full CRUD is NOT mandated**.
- **Gateway** — "An object that encapsulates access to an external system or resource." "Wrap all the special API code into a class whose interface looks like a regular object." Distinct from Repository: Gateways wrap external APIs; Repositories present a collection-like view of persisted domain objects.

Both are inner-layer ports a use case depends on; the outer data/framework layer implements them — DIP via Swift protocols owned in Nebula.

## `NebulaRepository<Element>` — PAT + existentials, NO hand-written `AnyRepository`

```swift
public protocol NebulaRepository<Element>: Sendable {
    associatedtype Element: Sendable
}
public protocol NebulaReadOnlyRepository<Element>: NebulaRepository<Element> {
    func stream() -> AsyncThrowingStream<Element, any Error>
    func count() async throws -> Int
}
public extension NebulaReadOnlyRepository where Element: NebulaEntity {
    func find(id: Element.ID) async throws -> Element? { /* default impl or requirement */ }
}
public protocol NebulaWritableRepository<Entity>: NebulaRepository<Entity> where Entity: NebulaEntity {
    func save(_ entity: Entity) async throws          // add-or-replace; NO separate update/create
}
public protocol NebulaDeletableRepository<Entity>: NebulaRepository<Entity> where Entity: NebulaEntity {
    func delete(id: Entity.ID) async throws
    func deleteAll(ids: some Sequence<Entity.ID>) async throws
}
```

- **Primary associated type** `Element` (Swift 5.7+ SE-0346; corroborated by `_Concurrency.swiftmodule:686` `AsyncSequence<Element, Failure>`). Below the `.v26` floor — a language feature, no `@available` gate.
- **`any NebulaRepository<E>` is `Sendable`** when `Element: Sendable` — compiler-verified (`swiftc -swift-version 6 -typecheck` clean). **No `@unchecked` on any Nebula-defined type.** This eliminates hand-written `AnyRepository<E>` for the common case (community guidance: prefer concrete / non-PAT / `any P` over hand-erased boxes; SE-0346 direction).
- **CQRS split** validated across community kits ([Lambdaspire CommandQueryDispatch](https://github.com/Lambdaspire/Lambdaspire-Swift-CommandQueryDispatch) `CQDQuery`/`HandlesQuery` vs `CQDCommand`/`HandlesCommand`, async throws). Caveat (verified): those kits use plain untyped `throws` with no `Sendable` markers — `Sendable` + typed errors here are **Nebula's binding-constraint-driven choices**, not a community-consistent attribute.
- **`NebulaReadOnlyRepository.Element` is unconstrained** (read models need not be `NebulaEntity`); `find(id:)` is a conditional requirement only when `Element: NebulaEntity`. Write/delete sub-protocols are constrained to `NebulaEntity` (identity required).
- **`NebulaDeletableRepository` is opt-in** — append-only/audit stores need not conform. No forced delete on read-only repos.

## Streaming: concrete `AsyncThrowingStream`, NOT `some AsyncSequence`

`some AsyncSequence` is **not permitted** in a protocol requirement signature (compiler error: "'some' type cannot be the return type of a protocol requirement; did you mean to add an associated type?" — verified by `swiftc -swift-version 6 -typecheck`). So a streaming requirement must return a **concrete** `AsyncThrowingStream<Element, any Error>`; implementers wrap their source via `AsyncThrowingStream.makeStream` (constrained to `Failure == any Swift::Error`, `_Concurrency.swiftmodule:1453`). Ground truth:
- `AsyncThrowingStream` `_Concurrency.swiftmodule:1402`, `Continuation: Sendable` `:1404`, `@unchecked Sendable where Element: Sendable` `:1460` (Apple's `@unchecked` — acceptable; Nebula defining a requirement returning it needs **no** `@unchecked` on a Nebula type).
- `AsyncStream` `:799`, `@unchecked Sendable where Element: Sendable` `:862`; `AsyncSequence` `:686`.
- All below the `.v26` floor (iOS 16/macOS 13 for `AsyncStream`/`Clock`).

## `NebulaRepositoryError` — open struct, bridges to CLOSED `NebulaError.Kind`

`NebulaError.Kind` is a closed `enum : String, Sendable, CaseIterable` (`Sources/Nebula/Errors/NebulaError.swift:57`, network/decoding/encoding/cocoa/file/validation/serialization/unknown; deprecation-runway comment `:55`). The binding **forbids adding cases**. So `NebulaRepositoryError` is an **open struct** with an **open `Kind`** (mirroring `NebulaLogCategory` — `Sources/Nebula/Logging/NebulaLogCategory.swift:28` `public struct NebulaLogCategory: Sendable, Hashable, ExpressibleByStringLiteral`, extensible-by-design comment `:21`), and it **bridges** to `NebulaError` via a **caller-picked** existing `Kind`:

```swift
public struct NebulaRepositoryError: Sendable, Error {
    public struct Kind: Sendable, Hashable, ExpressibleByStringLiteral {
        public let rawValue: String
        public init(_ rawValue: String) { self.rawValue = rawValue }
        // presets: .notFound, .alreadyExists, .storeFailure, .mapping, .constraintViolation, .cancelled, .unknown
    }
    public var kind: Kind
    public var message: String
    public var entityType: String?
    public var id: String?
    public var metadata: [String: String]
    public var underlying: NebulaError.Box?      // reuse the existing box (NebulaError.swift:95)
    // factory statics: .notFound(_:id:), .storeFailure(_:underlying:), .mapping(_:), .alreadyExists(_:id:)
}

extension NebulaError {
    public init(repositoryError: NebulaRepositoryError, kind: NebulaError.Kind)  // CALLER picks the bridging kind
}
```

- **Sendable**: derived — all fields Sendable (`Kind` open struct, `String`, `[String:String]`, `NebulaError.Box?` reused from `Sources/Nebula/Errors/NebulaError.swift:95`). **No `@unchecked`.**
- **No new `NebulaError.Kind` cases**: the caller picks the coarse kind at the boundary (`.cocoa` for persistence, `.network` for gateway, `.unknown` default). Fine taxonomy lives in the open `Kind.rawValue` (`"user.notFound"`, `"cache.miss"`). This is the open-struct-over-closed-enum principle at the repository dimension — see [[nebula-domain-error]].
- `NebulaError.wrap(_:)` (`Sources/Nebula/Errors/NebulaError+Mapping.swift:158`) is the lossless **sync** bridge to `Result<T, NebulaError>`; repository implementations `throw NebulaRepositoryError(...)` from untyped `throws` methods and callers wrap.

## `NebulaGateway` + 5th config pair

`NebulaGateway` is a method-free `Sendable` marker for external-API access (HTTP, third-party services) — no collection semantics, no `Element`, no aggregate identity. Concrete gateways define their own typed methods taking/returning DTOs + `NebulaError`, never framework types (a `URLSession.DataTaskPublisher` must not leak — the adapter maps it).

`NebulaGatewayConfiguration` mirrors the four existing config structs exactly (Sendable struct + `@Sendable` handler + fluent `.with*`) — fields: `endpoint: URL?`, `headers: [String:String]`, `decoder: NebulaJSONDecoder`, `encoder: NebulaJSONEncoder` (reusing the existing Codable edge — `Sources/Nebula/Extensions/Codable/NebulaJSONDecoderConfiguration.swift:36-38` documents a **derived** Sendable wrapper, no `@unchecked`), `logger: NebulaLogger?`, `timeout: Duration?`, `handler: @Sendable (NebulaErrorEvent) -> Void` (default capture-free). `NebulaGatewayConfig` is the process-wide `Mutex<NebulaGatewayConfiguration>` accessor (`static let current = Mutex<…>(.default)` — always `let`; `get()`/`set(_:)` via `current.withLock` `sending` SE-0430) — mirrors `NebulaErrorConfig` (`Sources/Nebula/Errors/NebulaErrorConfig.swift:23/26/31`).

`NebulaHTTPGateway` is an **optional** `Sendable` helper struct bundling a `NebulaGatewayConfiguration` + `URLSession` (`URLSession` is Sendable via Apple's `@unchecked` extension; held in `let` after configure-once, mirroring `NebulaJSONDecoder`'s freeze discipline). Provides `request(_:) async throws -> Data` mapping `URLError` → `NebulaRepositoryError` → `NebulaError`. URLSession is Foundation (no UIKit).

## Sendable strategy

- Protocols `: Sendable`; `any NebulaRepository<E>: Sendable` when `Element: Sendable` (compiler-verified).
- Concrete repos: `actor` (DB-backed shared state) or `Sendable struct` (in-memory/test — [[nebula-test-doubles]]).
- `NebulaRepositoryError`: derived `Sendable`, no `@unchecked`.
- `NebulaGatewayConfiguration`: derived `Sendable` (all fields Sendable; `NebulaJSONDecoder`/`Encoder` derived-Sendable). `NebulaGatewayConfig`'s `Mutex` is `let`.
- `NebulaHTTPGateway`: derived `Sendable` (no `@unchecked` on the Nebula type; URLSession held in `let`).

## Risks (see [[clean-architecture-toolkit-risks]])

- **`Sendable` PAT protocols resist `any Port` storage** in a type-erased composition root; a registry may need `@Sendable () -> Any` + `as!` (a code smell but unavoidable) — [[nebula-registry-di]].
- **Actor-boundary chafe**: `Sendable` repository protocols with async accessors push concrete repos toward `actor`; apps with synchronous CoreData/SQLite stacks may incur hop overhead. A sync sub-protocol may be needed.
- **`NebulaRepositoryError` bridging is lossy** for the original `any Error` (`DECISIONS.md` row 21) — documented behavior, but a recurring surprise that must be re-documented on this surface.
- **5th config symmetry temptation**: gateways are inherently multi-instance (different endpoints); a global `NebulaGatewayConfig` default may mislead. Open question whether `NebulaGatewayConfig` should exist at all ([[clean-architecture-open-questions]]).

## Open questions (see [[clean-architecture-open-questions]])

- ID constraint: `NebulaEntity.ID: Sendable & Hashable` sufficient, or a new `NebulaValue` marker? Recommend `Sendable & Hashable` unless `NebulaValue` earns a second use.
- `find(id:)` conditional on `Element: NebulaEntity`, or a separate `NebulaKeyedRepository<Element, ID>` for read models with synthetic keys?
- Typed-throws protocol variants (`throws(NebulaError)` / `throws(NebulaRepositoryError)`)? Recommend **NO** — one untyped-`throws` surface; consumers bridge via `wrap`/`Result`.
- Should concrete (non-protocol) repos return `some AsyncSequence` for flexibility? Does that complicate the `any NebulaReadOnlyRepository` existential's stream type?
- `NebulaHTTPGateway` in v1, or is `NebulaGateway` + config enough and HTTP left to consumers? An HTTP helper risks dragging in URLSession timeout/redirect policy surface needing platform gating.
- Repository policy cross-cutting (retry/backoff/cancellation, signpost tracing via `NebulaMeasureConfiguration`): a per-instance `NebulaRepositoryPolicy` Sendable struct, or consumer-composed? No global `Mutex` for repositories (multi-instance).

## Sources

- Martin Fowler, [Repository](https://martinfowler.com/eaaCatalog/repository.html), [Gateway](https://martinfowler.com/eaaCatalog/gateway.html) (verbatim-verified).
- [Lambdaspire CommandQueryDispatch](https://github.com/Lambdaspire/Lambdaspire-Swift-CommandQueryDispatch), [swift-ddd-kit](https://github.com/gradyzhuo/swift-ddd-kit) — CQRS read/write split validated (Sendable/typed-errors attributes NOT evidenced).
- [WWDC22-110353](https://developer.apple.com/videos/play/wwdc2022/110353/) — PATs + `any P<T>` existentials.
- `_Concurrency.swiftmodule` (Xcode 27 Beta 3): `AsyncSequence` `:686`, `AsyncStream` `:799/862`, `AsyncThrowingStream` `:1402/1404/1453/1460`.
- Nebula source: `NebulaError.swift:55/57/95`, `NebulaError+Mapping.swift:158`, `NebulaErrorConfig.swift:23/26/31`, `NebulaLogCategory.swift:21/28/30`, `NebulaJSONDecoderConfiguration.swift:36-38`.
- `DECISIONS.md` rows 21 (lossy mapping), 27 (Mutex accessor + explicit-param DI).

Source of truth = root docs (CLAUDE.md, ARCHITECTURE.md, DECISIONS.md, VERSIONING.md); this note is the synthesis. On conflict, the root doc wins.
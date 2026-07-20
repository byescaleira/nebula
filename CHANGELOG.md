# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0] - 2026-07-19

> Nebula 0.5.0 — aligned to OS 26 (Liquid Glass). The proper network layer:
> Endpoint / Client / Request / Response model (`NebulaHTTPEndpoint` /
> `NebulaHTTPRequest` / `NebulaHTTPResponse` / `NebulaHTTPClient` — non-generic,
> existential-friendly; verbs as default extensions, backward-compatible) + a
> per-endpoint cache (Nebula TTL / stale-while-revalidate metadata over the native
> `URLCache` — "Ambos") + a simple local HTTP/1.1 server over Network.framework
> (`NebulaHTTPServer` / `NWListener`). This release also folds in the previously-
> unreleased N1–N3 surface (retry / preferences / Aurora SwiftData); the 0.4.0
> milestone was not tagged separately. 635 Nebula tests / 127 suites + 12 Aurora
> tests / 3 suites green; zero concurrency warnings under Swift 6 mode.
> Build-verified on all 5 platforms (iOS/macOS/tvOS/watchOS/visionOS); DocC clean.

### Added — Wave N3 (persistence: Aurora sibling package — SwiftData)
- **`Aurora`** — a new local SwiftPM package (`Aurora/`, path-dep on Nebula,
  mirroring Meridian) that ships the SwiftData persistence adapter. The
  separation is load-bearing: `import Aurora` from inside Nebula is a **hard
  compile error** (Nebula's manifest is `dependencies: []` with no target
  depending on Aurora), so the Clean Architecture dependency rule — domain and
  use cases never import persistence — is compiler-enforced across packages.
  SwiftData is a system framework (not an SPM dep), so Aurora stays
  third-party-free. Versioning: Aurora N ↔ Nebula N ↔ OS N (policy finalized at
  N4, mirroring Meridian N ↔ Nebula N ↔ OS N).
- **`AuroraEntityMapping`** (`Aurora/Sources/Aurora/`) — a **type-level** protocol
  (static methods) bridging a SwiftData `@Model` (`PersistentModel`) to a Nebula
  `NebulaEntity` DTO: `toEntity` / `insert(_:in:)` / `update(_:from:)` /
  `descriptor(for:)` / `descriptor()`. Type-level so the repository holds no
  per-instance mapping state. The app conforms it per `@Model` type with a
  caseless `enum: AuroraEntityMapping, Sendable`.
- **`AuroraRepository<Mapping>`** (`Aurora/Sources/Aurora/`) — a `@ModelActor`
  `actor` generic over `Mapping: AuroraEntityMapping & Sendable`, conforming to
  `NebulaRepository` + `NebulaReadOnlyRepository` + `NebulaKeyedRepository` +
  `NebulaWritableRepository` + `NebulaDeletableRepository` (`Element =
  Mapping.Entity`). `@ModelActor` synthesizes the actor-isolated `ModelContext`
  and `init(modelContainer:)`. `stream()` is `nonisolated` (the port returns an
  `AsyncThrowingStream`, not `async`) and spawns a `Task` that hops to the actor;
  `count()` / `find(id:)` / `save(_:)` / `delete(_:)` are `async` on the actor.
  SwiftData's `@Model`/`ModelContext` are not `Sendable` (verified); the mapping
  bridges them to the `Sendable` `NebulaEntity` DTO so nothing non-`Sendable`
  escapes. SwiftData errors are rethrown untyped (Nebula's public-API posture).
- **`AuroraExample`** — a runnable end-to-end demo (`@Model` + `NebulaEntity` +
  mapping + in-memory `ModelContainer` + `AuroraRepository` CRUD round-trip);
  `swift run AuroraExample` is the N3 gate. Not a shipped product.
- Tests: `AuroraTests/AuroraRepositoryTests.swift` (12) — save (insert +
  add-or-replace by id), find (present/absent), count, stream (all/empty),
  delete (present/absent-no-op), port-conformance for all four capability ports
  (assign-to-existential + cast-back), Sendable-across-`Task`. 12 Aurora tests /
  3 suites green; zero concurrency warnings; release clean. Aurora has no
  `#if os()` (SwiftData + Foundation only).

### Added — Wave N2 (preferences: NebulaPreferences + NebulaDefaults)
- **`NebulaPreferences`** (`Architecture/Preferences/`) — a `Sendable` key-value
  preferences port: three byte-level requirements (`data(forKey:)` /
  `setData(_:forKey:)` / `remove(forKey:)`) plus a **default extension** that
  gives every conformer a `Codable` bridge (`value(_:forKey:)` /
  `setValue(_:forKey:)`, JSON through `Data`) and a `RawRepresentable` bridge
  (`rawValue(_:forKey:)` / `setRawValue(_:forKey:)`, `RawValue: Codable`). The
  seam is tiny on purpose — a test double, an iCloud key-value store, or an
  encrypted store conforms by implementing three methods and inherits the typed
  ergonomics. The Codable bridge uses plain `JSONEncoder`/`JSONDecoder` (Sendable,
  per-call), decoupled from the gateway's encoder configuration. Reads are
  lenient (`T?`, `nil` = absent, throws on corrupt); writes throw on encode;
  `setValue(nil)` / `setRawValue(nil)` removes the key.
- **`NebulaDefaults`** (`Architecture/Preferences/`) — the concrete
  `NebulaPreferences` façade over `UserDefaults`. `UserDefaults` is thread-safe
  but `@_nonSendable(_assumed)` in Swift 6, so it is wrapped in a
  `Mutex<UserDefaults>` (region-based isolation, the alternative to
  `@unchecked`) inside a `final class` that absorbs the `~Copyable` `Mutex`
  behind a copyable, `Sendable` reference (derived, **no `@unchecked`**). The
  initializer takes the `UserDefaults` `sending` (SE-0430) — ownership transfers
  at the call site, so the compiler rejects further use of that instance (no two
  regions racing on the same non-`Sendable` store).
- Tests: `ArchitecturePreferencesTests.swift` (17) — byte-level round-trip,
  Codable round-trip + absent→nil + corrupt→`DecodingError`, RawRepresentable
  String/Int round-trip + unmappable-raw→nil, an `InMemoryPrefs` `final class`
  proving the default extension works on a non-`UserDefaults` conformer, an
  existential holding both impls, and a Sendable-across-`Task` + 50-task
  concurrent-access smoke test. 574 tests / 118 suites green (+17 over N1); zero
  concurrency warnings under Swift 6 mode. New code has no `#if os()` (Foundation
  + Synchronization only).

### Added — Wave N1 (network: NebulaHTTPGateway + NebulaRetry)
- **`NebulaRetryPolicy` / `NebulaRetry` / `NebulaRetryJitter`** (`Architecture/Async/`) — a
  framework-agnostic retry loop for any `async throws` operation. `NebulaRetryPolicy` is a
  `Sendable` value (NOT `Equatable` — it stores a `@Sendable` `isRetriable` predicate, mirroring
  `NebulaGatewayConfiguration`): `maxAttempts` (total, including the first; clamped to ≥ 1),
  `baseDelay`, `multiplier`, `maxDelay`, `jitter` (`.none`/`.full`/`.equal`), and the predicate.
  `delay(forFailedAttempt:)` = `baseDelay * multiplier^index`, capped at `maxDelay`, then
  jittered. `NebulaRetry.withPolicy(_:sleeper:operation:)` retries on errors the predicate
  accepts, honors cancellation (`Task.checkCancellation()` before each attempt; a thrown
  `CancellationError` is never retried; a cancellation during `sleeper` propagates out), and
  rethrows the original error on exhaustion / for non-retriable errors. `sleeper` is injectable
  for tests (default `Task.sleep(for:)`). `defaultIsRetriable` retries transient `URLError`
  codes (`.timedOut`/`.cannotConnectToHost`/`.networkConnectionLost`/`.notConnectedToInternet`/
  `.dnsLookupFailed`/`.cannotFindHost`) + HTTP 408/429/500/502/503/504.
- **`NebulaHTTPGateway`** (`Architecture/Gateway/`) — the concrete `NebulaGateway` over
  `URLSession` the Wave H scaffold was built for. Foundation-only (no new framework import).
  `get`/`post`/`put`/`delete` (decode `T` or raw `Data`); reuses `NebulaGatewayConfiguration`'s
  `NebulaJSONDecoder`/`NebulaJSONEncoder`; retries via `NebulaRetry.withPolicy`; bridges
  `URLError` + HTTP status failures to `NebulaError` (kind `.network`, code domain
  `Nebula.HTTP`/`NSURLErrorDomain`) and reports them through the config's `handler`.
  `Sendable` derived (config + `URLSession` + policy all `Sendable` — no `@unchecked`).
- **`NebulaHTTPStatusError`** (`Architecture/Gateway/`) — `Error`/`Sendable`/`Equatable`
  carrying an HTTP status code, so the retry predicate distinguishes "transport failed"
  (`URLError`) from "server answered with an error status" and retries 5xx/408/429 selectively.
- Tests: `ArchitectureRetryTests.swift` (16) + `ArchitectureHTTPGatewayTests.swift` (13, over a
  `URLProtocol`-backed `URLSession` — no real network). 557 tests / 113 suites green (+32 over
  0.3.0); zero concurrency warnings under Swift 6 mode. New code has no `#if os()` (Foundation +
  Synchronization only).

### Added — Wave N7 (network: local HTTP server — Network.framework)
- **`NebulaHTTPServer`** (`Architecture/Network/`) — a simple local HTTP/1.1 server, the
  server-side counterpart to `NebulaHTTPGateway`. A `final class: Sendable` over `NWListener` /
  `NWConnection` (Network.framework — Foundation + Network, no SwiftUI / UIKit / new framework
  import). Listens on a TCP port, accepts connections, parses each request via
  `NebulaHTTPRequestParser` into a `NebulaHTTPRequest` (the **same value type the client
  builds**), dispatches it to a `@Sendable` handler, and writes the handler's `NebulaHTTPResponse`
  back as HTTP/1.1 bytes. Each connection runs in a `Task` (the callback-based `receive` / `send`
  are async-wrapped via `withCheckedContinuation`) and is closed after one response. `Sendable` is
  derived — `NWListener`, `NWConnection`, the `@Sendable` handler, and `DispatchQueue` are all
  `Sendable` at the `.v26` floor (no `@unchecked`); the one shared mutable state (the start-once
  flag) is a `Mutex`-guarded `final class` `OnceFlag` so `start()` resumes its continuation exactly
  once. `init(port:handler:)` (default 8080; pass `NWEndpoint.Port(rawValue: 0)` for an
  OS-assigned ephemeral port, then read `port` after `start()`), `start() async throws`
  (throws `NebulaHTTPServerError.bindFailed` if the port cannot bind), `stop()`. Scope is
  deliberately **"simple"**: plain HTTP/1.1, no TLS, no chunked transfer-encoding, no keep-alive
  (close after one response), `Content-Length` bodies only — a dev / test / full-stack-app tool,
  not a production server.
- **`NebulaHTTPRequestParser`** (`Architecture/Network/`, internal) — a bounded HTTP/1.1
  request parser (request line + headers + a `Content-Length` body, hand-rolled — no third-party
  dep). Returns `nil` when the buffer does not yet contain a complete request (the caller reads
  more and retries); throws `NebulaHTTPServerError.parseFailed` on malformed input. **Rejects
  negative, non-numeric, and oversized (`> 10 MiB`) `Content-Length` up front** — a negative value
  would otherwise build a reversed `Range` in `subdata(in:)` and trap the process (a crafted
  request must not crash the server). `maxBodyLength = 10 * 1024 * 1024`.
- **`NebulaHTTPServerError`** (`Architecture/Network/`) — the per-layer server error: a bind /
  parse / send failure surfaced by `NebulaHTTPServer`. An open-struct `Kind`
  (`bindFailed`/`parseFailed`/`sendFailed`/`cancelled`/`unknown`, `ExpressibleByStringLiteral`)
  plus a fine free-form `code`, conforming to `NebulaFailure, Equatable, Hashable` (mirrors
  `NebulaRepositoryError`). `coarseKind` maps bind/send → `.network`, parse → `.decoding`,
  cancelled/unknown → `.unknown`; `toNebulaError(kind:)` bridges to the closed `NebulaError.Kind`
  (no new `Kind` case). `NWError` is **not** `Sendable`, so it is never boxed across isolation —
  its description is folded into `message` (lossy, mirroring the gateway's `URLError` bridging).
- Serializer hardenings — `NebulaHTTPServer.serialize(_:)` overwrites any handler-provided
  `Content-Length` (case-insensitive) with the actual body count (no duplicate / stale header) and
  strips `\r\n` from handler-provided header names and values so a misbehaving handler cannot
  inject extra headers or a body.
- Tests: `ArchitectureHTTPServerTests.swift` — parser (complete GET / query items / POST body /
  incomplete headers→nil / incomplete body→nil / malformed request line / unsupported method /
  negative / non-numeric / oversized `Content-Length`), serializer (status line + headers + body,
  reason phrases, case-insensitive `Content-Length` overwrite, `\r\n` strip), error
  (`coarseKind` mapping, `toNebulaError` preserves kind+code, `NebulaError(error:)` dispatch,
  equality), and a **real localhost round-trip** (`NebulaHTTPServer` + `NebulaHTTPGateway` over
  `URLSession` — no `URLProtocol` stub; `@Suite(.serialized)`, OS-assigned ephemeral port): GET
  round-trip, POST echo, 404 → `NebulaError` `.network`, query items reach the handler.

### Added — Wave N6 (network: per-endpoint cache — Nebula over native URLCache)
- **`NebulaHTTPCachePolicy`** (`Architecture/Network/`) — the per-endpoint cache policy:
  `protocolDefault` (delegate to `URLSession`'s native HTTP cache), `bypass` (skip caching
  entirely), `store(ttl:)` (cache fresh for `ttl`), `staleWhileRevalidate(ttl:maxStale:)` (cache
  fresh for `ttl`, then serve stale within `maxStale` while revalidating in the background). A
  `Sendable, Equatable, Hashable` enum; defaulted on `NebulaHTTPEndpoint` to `.protocolDefault`,
  overridable per request.
- **`NebulaHTTPCache`** (`Architecture/Network/`) — the cache **port**: a `Sendable` collaborator
  the gateway consults before a network fetch and stores into after one. `response(for:policy:)`
  returns a `NebulaCachedResponse` (a response paired with `isStale`) or `nil`; `store`,
  `remove(for:)`, `removeAll`. The `isStale` flag lets the gateway serve a stale hit immediately
  and revalidate in a background `Task` only when the entry is actually stale, not on every fresh
  hit. Nebula owns the TTL / stale-while-revalidate **metadata**; a concrete façade holds the
  response **bytes**.
- **`NebulaURLCache`** (`Architecture/Network/`) — the concrete `NebulaHTTPCache` façade over the
  native `URLCache` ("Ambos — Nebula sobre nativo"): a `final class` wrapping `Mutex<State>`
  where `State` holds the native `URLCache` plus Nebula's metadata map (one lock so a hit reads
  both atomically and a store writes both atomically). `URLCache` is thread-safe but **not
  `Sendable`** in Swift 6 (verified against the Xcode 27 Beta 3 `.swiftinterface` — only a
  convenience `init` extension, no `Sendable` conformance), so the `Mutex` provides the
  synchronization boundary (region-based isolation, the alternative to `@unchecked`) and the
  `final class` derives `Sendable` with **no `@unchecked`** (the `NebulaDefaults` / `NebulaSpyUseCase`
  precedent). `init(_ cache: sending URLCache = .shared)` (SE-0430 — ownership transfers at the
  call site). Fresh within TTL; stale within `ttl + maxStale` (returns `isStale == true`); beyond
  that, `nil`. Orphaned metadata is cleaned up if the native cache evicted the bytes.
- **Gateway `send` integration** — `NebulaHTTPGateway` gains an optional `cache: NebulaHTTPCache?`
  constructor arg (default `nil` — no Nebula caching; `URLSession`'s native protocol cache still
  applies) and a `withCache(_:)` builder. When a cache is injected, `buildRequest` sets
  `URLRequest.cachePolicy = .reloadIgnoringLocalCacheData` for `.store` / `.staleWhileRevalidate`
  so **Nebula's TTL wins over the native cache** (Nebula is authoritative). `send` consults the
  cache for cacheable policies: a fresh hit returns without a network fetch; a stale hit returns
  the stale response **and** kicks a `Task.detached` background revalidate-and-store (detached, not
  `Task {}`, so a `@MainActor` consumer does not get the store hopping to main); a 2xx response is
  stored. `.protocolDefault` / `.bypass` skip the Nebula cache.
- Tests: `ArchitectureHTTPCacheTests.swift` (10) — store→fresh, miss when nothing stored, expired
  →nil (1 ms TTL), stale-while-revalidate returns stale within `maxStale`, stale beyond `maxStale`
  →nil, `remove` drops an entry, `removeAll` drops everything, `protocolDefault` / `bypass` are
  not Nebula-managed, `store` declines for a non-Nebula-managed policy (dedicated in-memory
  `URLCache` per test, `@Suite(.serialized)`) + 5 gateway cache integration tests in
  `ArchitectureHTTPGatewayTests` (fresh hit skips network, cache miss fetches + stores, bypass
  skips cache, stale hit serves + revalidates in the background, store policy without a cache still
  fetches).

### Added — Wave N5 (network: Endpoint / Client / Request model + gateway refactor)
- **`NebulaHTTPMethod`** (`Architecture/Network/`) — `enum: String, Sendable, Equatable, Hashable`
  (get / post / put / patch / delete / head).
- **`NebulaHTTPEndpoint`** (`Architecture/Network/`) — the **port**: a `Sendable` type that
  builds a `URLRequest` against a base URL (`func urlRequest(against baseURL: URL?) throws ->
  URLRequest` — the `URLRequestConvertible` idea). Non-generic so `any NebulaHTTPEndpoint` is a
  usable existential. `cachePolicy` is a default extension (`.protocolDefault`), overridable by
  conformers — a protocol requirement, not just a default extension, so existential
  witness-table dispatch honors a conformer's override.
- **`NebulaHTTPRequest`** (`Architecture/Network/`) — the concrete **value type**
  (`struct: NebulaHTTPEndpoint, Sendable, Equatable`): `method` / `path` / `query:
  [URLQueryItem]` / `headers: [String: String]` / `body: NebulaHTTPBody` / `cachePolicy`.
  `urlRequest(against:)` resolves the URL (relative → baseURL, absolute path, query appended not
  replaced — replicates the Wave N1 resolution so existing tests pass). **Reused as the
  server-side parsed-request type** — the client and the local server share one request shape.
- **`NebulaHTTPBody`** (`Architecture/Network/`) — `enum: Sendable, Equatable { none, data(Data,
  contentType:), static func json(_:using:) throws }`. `.json` encodes **eagerly** so the value
  stays `Sendable` (the `Encodable` is consumed, not stored).
- **`NebulaHTTPResponse`** (`Architecture/Network/`) — `struct: Sendable, Equatable { statusCode,
  headers, body: Data }` + a generic `decode<T: Decodable & Sendable>(_:using:)`.
- **`NebulaHTTPClient`** (`Architecture/Network/`) — the **client port**: `protocol
  NebulaHTTPClient: NebulaGateway` with `send(_ endpoint:) async throws -> NebulaHTTPResponse` as
  the one transport requirement (non-generic, existential-friendly — the Point-Free `send(_:)->
  Response` shape; the [[nebula-aurora-swiftdata]] work proved `associatedtype`-returning methods
  cannot be called on `any` existentials under Swift 6.2). Default extensions: `send<T: Decodable
  & Sendable>(_:as:)` (decode) + the **verb conveniences** (`get` / `get(_:as:)` / `post` /
  `put` / `delete`) building a `NebulaHTTPRequest` and delegating to `send` — **preserving the
  Wave N1 verb signatures** so call sites are backward-compatible. The codec requirements let the
  verbs use the configured `NebulaJSONEncoder` / `Decoder` (configure-once-and-freeze preserved).
- **`NebulaHTTPGateway` refactor** (`Architecture/Gateway/`) — now conforms to `NebulaHTTPClient`.
  The verb methods move off the struct onto the `NebulaHTTPClient` default extension; the struct's
  one new requirement is `send(_:)`. `send`: `buildRequest` (endpoint → `URLRequest`, merge config
  headers for keys the request didn't set — **per-request headers override config defaults**;
  apply config `timeout`; map `cachePolicy` → `URLRequest.cachePolicy`) → `NebulaRetry.withPolicy`
  around `session.data(for:)` → `validate` (2xx) → `NebulaHTTPResponse`. Error bridging unchanged
  (`NebulaHTTPStatusError` / `URLError` / fallback → `NebulaError` kind `.network`, reported via
  `configuration.report(_:)`; no new `Kind` case).
- Tests: `ArchitectureNetworkTests.swift` — endpoint → `URLRequest` building (relative / absolute
  / query / headers / body / cache policy), response `decode`, client `send(_:as:)` decode + the
  verb conveniences; existing `ArchitectureHTTPGatewayTests` pass unchanged (verb signatures
  preserved).

### Added — Wave N8 (governance — DocC + ADR + final gate)
- DocC articles `ArchitectureNetwork.md` / `ArchitectureHTTPCache.md` / `ArchitectureHTTPServer.md`
  (indexed in `Architecture.md` after `ArchitectureGateway`); ADR in `DECISIONS.md`
  (Network layer, Waves N5–N8, Accepted); `ARCHITECTURE.md` `Network/` subtree row + structure tree
  + Data + Network prose; this roadmap. Vault `03-padroes/nebula-network-endpoint-client.md`
  marked `status: shipped` / `shipped: "0.5.0"`; `vault/Home.md` index updated.
- Tests: 635 Nebula tests / 127 suites green (+61 over N3's 574 / 118); zero concurrency warnings
  under Swift 6 mode. New code has no `#if os()` (Foundation + Network + Synchronization only).
  Release clean; build-verified on all 5 platforms (iOS/macOS/tvOS/watchOS/visionOS); DocC
  `xcodebuild docbuild` succeeds (new articles resolve).

## [0.3.0] - 2026-07-19

> Nebula 0.3.0 / Meridian 0.3.0 — aligned to OS 26 (Liquid Glass). Presentation
> architecture: MVVM `@Observable` + native typed-`[Route]` Router (no Coordinator
> tree), shipped as Foundation-only seams in Nebula + a sibling **Meridian**
> SwiftPM package that owns SwiftUI. `import Meridian` from Nebula is a hard
> compile error → the Clean Architecture dependency rule is compiler-enforced
> across packages. The `NebulaRouter` port is **async** so the `@MainActor
> @Observable` Meridian `Router` conforms while Nebula stays `@MainActor`-free.
> 525 Nebula tests / 13 Meridian tests green; zero concurrency warnings under
> Swift 6 mode. Build-verified on all 5 platforms (iOS/macOS/tvOS/watchOS/visionOS).

### Added — Wave I (presentation architecture, Foundation-only seams)
- **Architecture/Presentation** — the Foundation-only presentation half of the
  data-driven `Router` pattern (the sibling **Meridian** package, Wave II, owns
  the `@Observable Router` + `NavigationStack` wiring). Five symbols, all pure
  `import Foundation` (+ `import Synchronization` for the spy):
  - `NebulaRoute` — `protocol: Hashable, Sendable, Codable`; the route contract
    an app's `Route` enum conforms to (push identifier values, render models).
  - `NebulaNavigationStack<Route>` — a typed `[Route]` navigation **model** as a
    `Sendable`/`Codable`/`Equatable` value type: `push`/`pop`/`popToRoot`/
    `replaceStack`. Stack logic in `static func …(into: inout [Route])` — single
    source of truth shared by the instance API and (Wave II) the `@Observable`
    Router. Deep links = "build `[Route]`, `replaceStack`" — pure data, testable
    without a simulator. Typed `[Route]` preferred over type-erased
    `NavigationPath` (compile-time exhaustive handling, inspectable/reorderable
    stack — defensive vs `NavigationStack`'s reported macOS bugs, risk #4).
  - `NebulaRouter<Route>` — the navigation-intent **port**, primary associated
    type `Route` (SE-0346), `Sendable`, with **`async`** requirements
    (`push`/`pop()`/`pop(_:)`/`popToRoot`/`replaceStack`). Async is the Swift 6
    way to let a `@MainActor @Observable` concrete `Router` (Meridian) satisfy a
    nonisolated, Foundation-only port: a synchronous `@MainActor` method witnesses
    a nonisolated `async` requirement (the `await` hops to the main actor), so
    Nebula stays free of `@MainActor` (app supplies isolation) yet the on-actor
    router conforms. The async port is also the cross-actor bridge for off-actor
    deep-link parsers. Conformers keep **synchronous** implementations (a sync
    method witnesses an async requirement) — concrete calls stay sync.
  - `NebulaViewModel` — bare `Sendable` marker; Nebula ships **only the marker**
    (NOT `@Observable` — Swift 6 friction outside SwiftUI; the consumer adds
    `@MainActor @Observable`).
  - `NebulaSpyRouter<Route>` — spy router recording every intent as a value
    (`Intent` enum `Sendable`/`Equatable`); `final class` + `let Mutex`,
    `Sendable` **derived** (no `@unchecked`), mirroring `NebulaSpyUseCase`.
    Conforms to `NebulaRouter` — a drop-in substitute for the port in tests.
- Tests: `ArchitecturePresentationTests.swift` — navigation model ops, deep-link
  `replaceStack`, `Codable` round-trip (state restoration), `Sendable`-across-
  tasks, spy intent recording, and port-conformance through `any NebulaRouter<R>`.
  525 tests / 110 suites green (+16 over 0.2.0); zero concurrency warnings under
  Swift 6 mode. New files have no `#if os()` (Foundation + Synchronization only).

### Added — Wave II (Meridian, the presentation-architecture sibling package)
- **`Meridian/`** — a NEW separate local SwiftPM package (its own `Package.swift`,
  module graph, and DocC catalog) in this repo, depending on Nebula via
  `.package(name: "Nebula", path: "../")`. Where Nebula is Foundation-only,
  Meridian swallows SwiftUI. `swift-tools-version: 6.3`, language mode v6, all 5
  platforms `.v26`, `defaultLocalization: en`; `dependencies` lists only the local
  Nebula sibling (SwiftUI is a system framework, not an SPM dep) → third-party-free.
  One repo / one CI lane builds both; promoting Meridian to its own git repo for
  public consumption is a documented future step (the `path` dep becomes a URL).
  The separation is load-bearing: `import Meridian` from inside Nebula is an
  **unconditional hard compile error** (Nebula `dependencies: []`), so the Clean
  Architecture dependency rule (use cases/domain never import presentation) is
  compiler-enforced across packages — closing the Wave H open risk (SR-1393 only
  applies within one package's shared `.build`). Mirrors `swift-navigation`.
- `Router<Route: NebulaRoute>` — `@MainActor @Observable final class` conforming to
  `NebulaRouter<Route>`; owns the observation-tracked `var path: [Route]`; intent
  methods (`push`/`pop()`/`pop(_:)`/`popToRoot`/`replaceStack`) delegate to
  `NebulaNavigationStack` statics (single source of truth shared with the pure-Swift
  model). `Sendable` by `@MainActor` isolation (no `@unchecked`). The data-driven
  Router pattern — one per tab — NOT a Coordinator tree (owner preference).
- `MeridianNavigationStack<Route, Root, Destination>` — a `View` wiring
  `NavigationStack(path: $router.path)` + `navigationDestination(for: Route.self)`
  with a `@ViewBuilder` destination resolver (the type-driven view factory).
- **Async port conformance fix**: `NebulaRouter`'s requirements are `async`
  (Wave I) precisely so this `@MainActor` `Router` can conform to a nonisolated,
  Foundation-only port — a synchronous `@MainActor` method witnesses a nonisolated
  `async` requirement (the `await` hops to the main actor). Nebula stays free of
  `@MainActor`; the async port doubles as the cross-actor bridge for off-actor
  deep-link parsers. Conformers keep sync impls — concrete calls stay synchronous.
- Tests: `Meridian/Tests/MeridianTests/RouterTests.swift` — push/pop/replaceStack
  as data, deep-link, port-conformance through `any NebulaRouter<R>` (async hop),
  `@MainActor` Sendable, `Codable` path round-trip. 6 tests / 1 suite green; zero
  concurrency warnings. `@Suite @MainActor` (constructing `Router` requires the
  main actor).

### Added — Wave III (destinations + deep-link + example)
- **`MeridianExample`** — a runnable executable target demonstrating the full
  pattern: `Router<AppRoute>` + `MeridianNavigationStack` + a type-driven
  `Destination` enum driving `sheet(item:)` ("impossible states unrepresentable")
  + an `onOpenURL` deep-link handler. `@main App`; compiling it is the Wave III
  gate; `swift run MeridianExample` launches the macOS app. NOT a shipped product.
- **Type-driven destinations** (pattern): a single `Optional<Destination>` enum
  per feature drives `sheet(item:)` — only one destination active, compiler-
  enforced (no `@CasePathable` macro — `dependencies: []`; `Identifiable` hand-
  rolled). Documented in `Meridian.docc/NavigationPatterns.md`.
- **Deep-link-as-data** (pattern): a pure `URL → [Route]` parser; `replaceStack`
  is the deep-link primitive; the async `NebulaRouter` port is the cross-actor
  bridge to the `@MainActor` router. `Codable` `Route` → state restoration.
- Tests: `Meridian/Tests/MeridianTests/DeepLinkTests.swift` — deep-link parse →
  `[Route]` assertions, `replaceStack` via the async port, `Destination`
  `Identifiable` + single-optional "impossible states" assertions. 7 new tests
  (13 total / 3 suites in Meridian), zero warnings.

## [0.2.0] - 2026-07-19

The **Clean Architecture toolkit** — the second surface of Nebula (foundation + architecture). A new
`Sources/Nebula/Architecture/` subtree ships the **seams** that help — and let — an app implement
Clean Architecture efficiently, without Nebula owning any presentation, database, or framework code.
Concrete adapters (repositories, gateways, presenters, URLSession networking) live in the app; Cosmos
is the presentation layer. Presentation patterns (MVVM / MVC / VIP / VIPER) are explicitly out of scope.
The toolkit is pure Swift + Foundation + `Synchronization`; every symbol sits at the Nebula 26 floor
(no above-floor gates). 509 tests / 107 suites green; zero concurrency warnings under Swift 6 mode.
Wave H complete — see `ROADMAP.md`. ADR in `DECISIONS.md`.

### Added
- **Architecture/Domain** — `NebulaValue` / `NebulaEntity` / `NebulaAggregate` markers + `NebulaID<Entity>`
  phantom-typed UUID identity (1-param — generic-parameter defaults are rejected on this toolchain,
  verified `swiftc -parse`; `Codable` intentionally not conformed on the type).
- **Architecture/Ports** — bare `Sendable` markers `NebulaInputPort` / `NebulaOutputPort` / `NebulaDTO`.
  Nebula defines no presenter.
- **Architecture/Errors** — `NebulaFailure: Error, Sendable` protocol + per-layer open structs
  `NebulaDomainError` / `NebulaValidationError` (`Sendable`/`Equatable`/`Hashable` derived) bridging to
  the CLOSED `NebulaError.Kind` enum via a caller-picked `toNebulaError(kind:)` — NO new `Kind` cases.
  `NebulaError.init(error:)` dispatches `NebulaFailure` before the `NSError` fallback.
- **Architecture/UseCase** — `NebulaUseCase<I, O>` generic `Sendable` struct over a `@Sendable`
  `(I) async throws -> O` body (NOT a protocol + `AnyUseCase` box) + `NebulaUseCaseRole` closed
  command/query enum + `NebulaUseCaseBody` typealias; `execute(_:)` (untyped `throws`) and
  `executeTyped(_:) async throws(NebulaError)` (SE-0413, preserves a thrown `NebulaError`, bridges
  others via `NebulaError(error:)`). Decorators `.logged(using:)` / `.measured(using:)` /
  `.reported(using:)` / `.instrumented(using:measure:error:)` route to the EXISTING log/measure/error
  configs (NO 5th config); `.instrumented` composes `reported().measured().logged()`.
- **Architecture/Repository** — PAT `NebulaRepository<Element>: Sendable` + capability sub-protocols
  `NebulaReadOnlyRepository` (`stream()`/`count()`) / `NebulaKeyedRepository` (`find(id:)` requirement,
  `Element: NebulaEntity`) / `NebulaWritableRepository` (`save(_:)`, no `update` verb) /
  `NebulaDeletableRepository` (`delete(_:)`). `stream()` returns concrete `AsyncThrowingStream` (a
  `some AsyncSequence` return is illegal in a protocol requirement). `NebulaRepositoryError`
  (`Source` enum `.local`/`.remote`/`.unknown`; open `Kind` with presets `.notFound`/`.alreadyExists`/
  `.storeFailure`/`.mapping`/`.constraintViolation`/`.cancelled`/`.unknown`; factory statics) conforming
  to `NebulaFailure`.
- **Architecture/Gateway** — `NebulaGateway` marker + `NebulaGatewayConfiguration` (Sendable ONLY — NOT
  `Equatable`, mirrors `NebulaErrorConfiguration`; reuses `NebulaJSONDecoder`/`NebulaJSONEncoder`;
  `.with*` builders + `report(_:)`) + `NebulaGatewayConfig` process-wide `Mutex` accessor.
- **Architecture/Validation** — `NebulaValidator<T>` (sync, `Rule` closures, `validate(_:)`
  short-circuits on the first failing rule, `+` composes) + `NebulaAsyncValidator<T>` (async,
  `AsyncRule` closures may `await`/`throw`; a thrown I/O error propagates out — it is NOT a `.failure`).
- **Architecture/Registry** — `NebulaRegistryKey` (open `Sendable` `ExpressibleByStringLiteral` struct,
  mirrors `NebulaLogCategory`; presets `.repository`/`.gateway`/`.useCase`) +
  `NebulaRegistryConfiguration` (Sendable ONLY, transient `@Sendable () -> Any` factories,
  `.withFactory(for:_:)`) + `NebulaRegistry` (explicit constructor-injection `resolve(_:as:)`) +
  `NebulaRegistryConfig` (process-wide `Mutex` accessor). DI **without** a container.
- **Architecture/Testing** — in-target test doubles `NebulaFakeRepository` (keyed/writable/deletable
  in-memory; `final class` + `let Mutex`, `Sendable` **derived** — final class with all-`let`
  `Sendable` properties, no `@unchecked`) /
  `NebulaStubUseCase` (canned `Result<O, NebulaError>`, `execute` + `executeTyped`) /
  `NebulaSpyUseCase` (records inputs, `callCount`/`inputs()`, delegates to `body`). Ship in the main
  target (decision #8).
- **Architecture/Async** — `NebulaResultPipeline<T: Sendable>` (`map`/`flatMap`/`recover` `@Sendable`
  async transforms over `Result<T, NebulaError>`; `map` bridges thrown errors via `NebulaError(error:)`;
  `.failure` short-circuits) + `AsyncSequence.nebulaChunked(byCount:)` / `nebulaUniqued(on:)` /
  `nebulaUniqued()` (constrained `Self: Sendable, Element: Sendable`, return concrete
  `AsyncThrowingStream`; `nebula*` prefix — no stdlib pollution).
- **DocC** — `Architecture.md` canonical article + 10 per-subsystem articles
  (`ArchitectureDomain`/`Ports`/`Errors`/`UseCase`/`Repository`/`Gateway`/`Validation`/`Registry`/
  `Testing`/`Async`); linked from the module root `Nebula.md`.
- **Governance docs** — `ARCHITECTURE.md` (Architecture section), `DECISIONS.md` (Wave H ADR,
  Accepted), `ROADMAP.md` (Wave H shipped), `VERSIONING.md` (toolkit at-floor row). Vault: 11
  architecture notes marked shipped.

### Deferred (not in 0.2.0; tracked in `ROADMAP.md` → "Later")
- `NebulaInvariant` (decision #6 — validator ergonomics).
- `NebulaMockRepository` (decision #8 — ship Fake/Stub/Spy only in v1).
- `NebulaHTTPGateway` (decision #8-resolved — ship the seam only; the app provides URLSession).
- `NebulaCancellation` / `NebulaError.wrapAsync` (decision #13 — reuse `Task.checkCancellation()` and
  inline do/catch).
- Template multi-module `Domain` product (decision #10 — single-target; document the recommended
  app `Domain` module).

## [0.1.0] - 2026-07-18

First tagged release. The first **complete** Nebula foundation: the four `Sendable` configuration
contracts, the `NebulaError` envelope with lossy mapping, the seven extension groups, `NebulaStandards`,
`NebulaMeasureConfiguration`, the DocC catalog, and the GitHub CI matrix. 379 tests green; zero
concurrency warnings under Swift 6 mode. Waves A–G complete — see `ROADMAP.md`.

### Added
- **Package scaffold** — SPM package `Nebula` for Apple v26 platforms (iOS / macOS / tvOS /
  watchOS / visionOS, all `.v26`); `swift-tools-version: 6.3` (dual Xcode 26.4+ / Xcode 27 build;
  OS-27-only SDK symbols compile-gated `#if swift(>=6.4)` — graceful fallback on Swift 6.3,
  enabled on Swift 6.4); `swiftLanguageModes: [.v6]`; `defaultLocalization: "en"`; single
  `Nebula` target + `NebulaTests` (Swift Testing); no third-party dependencies;
  `.process("Resources")` commented out (foundation emits developer-facing English log/error
  text; no String Catalog by default — the deliberate divergence from Cosmos, which ships
  `.xcstrings` for UI strings).
- **Sources/Nebula folder tree** — `Nebula.swift` (top-level `Nebula` enum + `NebulaVersion`),
  `Logging/`, `Errors/`, `Extensions/{DateTime,String,Number,Primitive,Collection,Codable,DataURL}/`,
  `Standardize/`, `Measure/`, `Nebula.docc/` (internal physical boundaries, not module
  boundaries — one `import Nebula`).
- **NebulaVersion** — `NebulaVersion(major: 26, minor: 0, patch: 0)` in the top-level `Nebula.swift`
  (Nebula N == OS N baseline; the canonical `@available(iOS 26, macOS 26, tvOS 26, watchOS 26,
  visionOS 26, *)` spelling lives in `CLAUDE.md`/`VERSIONING.md`).
- **Logging** — `NebulaLogConfiguration` (level, category, subsystem, min level, `@Sendable`
  handler, fluent `.with*`, `logger()`/`log(_:_:)`) + `NebulaLogConfig` process-wide `Mutex`
  accessor; `NebulaLogger` (Sendable struct over `os.Logger` — exposes `osLogger` for the
  redaction-preserving `OSLogMessage` path and `String` convenience level methods for the simple
  path; `os.Logger` cannot be wrapped, compile-verified); `NebulaLogLevel`, `NebulaLogCategory`,
  `NebulaLogEvent`; `NebulaSignposter`/`NebulaSignpostID`/`NebulaSignpostIntervalState`/
  `NebulaSignpostMetadata` (typealias = `os.SignpostMetadata`); `NebulaMemoryLogHandler` (`final
  class @unchecked Sendable`, `Mutex<T>`-backed ring buffer; test/preview-only).
- **Errors** — `NebulaError` (`Error`/`LocalizedError`/`CustomNSError`/`Sendable`/`Hashable`) +
  nested `Code`/`Kind`/`Context`/`Box` (final class — struct recursion illegal); lossy mapping
  inits from `NSError`/`DecodingError`/`URLError`/`CocoaError`/`any Error` + `EncodingError`;
  `NebulaError.wrap(_:) -> Result<T, NebulaError>`; `NebulaErrorConfiguration` (Sendable ONLY —
  NOT `Equatable`) + `NebulaErrorEvent` (Sendable + Equatable) + fluent `.with*`; `NebulaErrorConfig`
  process-wide `Mutex` accessor; `NebulaDecodingError`/`NebulaEncodingError`.
- **Extensions — DateTime** — `Date` arithmetic/predicates (DST-safe via
  `calendar.dateInterval(of:for:)`); `DateComponents` builders;
  `DateInterval.init(start:duration: Swift.Duration)`; `NebulaDateFormat`/`NebulaDurationFormat`
  façades. ISO/stable presets pinned to `Locale(identifier: "en_US_POSIX")` + `.gmt`.
- **Extensions — String** — `isBlank`/`nilIfEmpty`/`trimmed`/`truncated(to:with:)`/case
  conversions/base64/hex/URL extraction; `NebulaRegex<Output>` (Sendable, conditional `where
  Output: Sendable`); `NebulaRegexPatterns` (curated literals — UUID/IPv4/hex/semver/ISO-timestamp;
  NO email); `NebulaStringDetectedEntity` over `NSDataDetector` (cached in `Mutex<NSDataDetector?>`);
  `NebulaStringLocalization` (Foundation scope only — no SwiftUI/UIKit scopes).
- **Extensions — Number** — `NebulaFormattingOptions` (Sendable + `.with*`); `NebulaNumberFormatting`
  façade (percent/currency/bytes/list/measurement — no legacy Formatter subclasses; `ListFormatter`
  per-call only, never cached); `BinaryInteger`/`BinaryFloatingPoint`/`Decimal` extensions;
  `Decimal.rounded(toDecimalPlaces:)` via `NSDecimalRound` + `NebulaDecimalRoundingRule` enum
  mapping 1:1 to `NSDecimalNumber.RoundingMode`.
- **Extensions — Primitive** — `Comparable.clamped(to:)`; `BinaryInteger.isEven`/`isOdd`/
  `times(_:)`; `Optional.or(_:)`/`orThrow(_:)`/`isNilOrEmpty`; `NebulaNilError` (concrete
  Sendable); `UUID.shortString`/`isValid(_:)`. NEVER redeclares `Bool.toggle()`/`isMultiple(of:)`.
- **Extensions — Collection** — `nebulaChunked`/`nebulaWindows`/`nebulaUniqued`/
  `nebulaStablePartition`/`nebulaPartitioned`/`nebulaSorted`/`nebulaMerging`. `nebula*` prefix on
  open `Collection`/`Sequence` ergonomics (no stdlib pollution); eager by default; non-escaping
  `rethrows`. (`nebulaFiltered(by:)` over `Foundation.Predicate` and `NebulaFrequency` were deferred
  to post-0.1.0 — see ROADMAP.)
- **Extensions — Codable** — `NebulaJSONDecoder`/`NebulaJSONEncoder` (Sendable wrappers holding a
  configure-once-frozen `JSONDecoder`/`JSONEncoder` in a `let`);
  `NebulaJSONDecoderConfiguration`/`NebulaJSONEncoderConfiguration` (Sendable + `.with*`, all
  strategy enums Sendable); `Decodable.init(fromJSON:)`/`Encodable.toJSONData`/`toJSONString`/
  `Data.asPrettyJSONString`. NO `OutputFormatting.fragmentsAllowed` (does not exist).
- **Extensions — Data/URL** — `Data.nebulaHexEncodedString`/`init?(nebulaHexEncoded:)` (Foundation
  has NO native hex); `NebulaHashAlgorithm` (Sendable enum over CryptoKit SHA256/384/512 — the
  ONLY `import CryptoKit`); `Data.nebulaDigest`/`nebulaHexDigest`;
  `URL.nebulaAppending(queryItem:)`/`nebulaSettingQueryItem`/`nebulaRemovingQueryItem`/
  `nebulaPercentEncoded()`; `URLComponents.nebulaWith(queryItem:)` fluent builders.
- **Standardize** — `NebulaStandards` (formatting façade over the modern `FormatStyle` family;
  `.withLocale`/`.withTimeZone`/`.withCalendar`; typed accessors only — no polymorphic
  `.format(_:)`) + `NebulaStandardsConfig` (process-wide `Mutex` accessor). DateComponents
  accessors gated `@available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)`.
- **Measure** — `NebulaMeasureConfiguration` (the 4th config struct — carries
  `measure(_:operation:)`/`bench(_:iterations:warmup:operation:)` ON the config, mirroring
  `NebulaLogConfiguration.log`; NO separate `NebulaMeasure` type) + `NebulaMeasureResult`
  (minimal: name/iterations/total/perIteration — no p50/p99 yet) + `NebulaMeasureConfig`
  (process-wide `Mutex` accessor).
- **Above-floor gates (Nebula 26.4)** — `Data.Base64EncodingOptions.base64URLAlphabet`/
  `.omitPaddingCharacter`, `String.Encoding.ianaName` getter AND `init?(ianaName:)`,
  `UUID.random(using:)`, all gated `@available(iOS 26.4, macOS 26.4, tvOS 26.4, watchOS 26.4,
  visionOS 26.4, *)`.
- **DocC catalog** — `Sources/Nebula/Nebula.docc/` (auto-discovered by SwiftPM because it is
  inside the target's source directory); root article + subsystem articles. Built natively in
  Xcode 26/27; CLI generation via `xcodebuild docbuild` (no `swift-docc-plugin` —
  `Package.swift` keeps `dependencies: []` pristine).
- **GitHub CI** — `.github/workflows/ci.yml` — 5-platform matrix (iOS/macOS/tvOS/watchOS/visionOS)
  + `swift build -c release` to exercise `#if os()` coverage; Xcode 26.4+ pinned.
- **Governance docs** — `CLAUDE.md` (binding guidelines), `ARCHITECTURE.md`, `DECISIONS.md`,
  `VERSIONING.md`, `ROADMAP.md`, `CONTRIBUTING.md`, `PROPOSAL.md`, `README.md`, `CHANGELOG.md`.
- **Obsidian vault MOC** — `vault/Home.md` + 12 verified research notes across `01-fundamentos/`
  (10 foundation subsystems) and `03-padroes/` (2 patterns: `nebula-spm-architecture`,
  `nebula-swift6-concurrency`), each adversarially re-verified against the Xcode 27 Beta 3 SDKs.
  The `.swiftinterface` is the authoritative ground truth; WebFetch-sourced availability tables
  were rejected where they conflicted (UUID.random, percentEncodedQueryItems,
  `OutputFormatting.fragmentsAllowed`, `convertFromKebabCase`, `base64Encode`, a parameterless
  `UUID.random()`, "UUID is not Comparable" — all hallucinated).

### Deferred (not in 0.1.0; tracked in `ROADMAP.md` → "Later")
- `NebulaLogStoreExporter`/`NebulaLogStoreEntry` (macOS-only log-store exporter; `#if os(macOS)`
  + explicit per-platform unavailable).
- `NebulaLocked<Value>`/`NebulaFlag`/`NebulaOnce` (`~Copyable`/`Sendable` concurrency wrappers
  around `Mutex`/`Atomic`).
- `NebulaClock` (ContinuousClock/SuspendingClock wrapper — measure currently uses
  `any Clock<Duration>` directly).
- `NebulaMeasureResult` distribution stats (min/max/mean/p50/p99).
---
tags: [nebula, network, architecture, swift, clean-architecture, http]
aliases: [nebula endpoint client, NebulaHTTPClient, NebulaHTTPEndpoint, NebulaHTTPRequest, NebulaHTTPServer, NebulaHTTPCache, NebulaURLCache, NebulaHTTPCachePolicy, NebulaHTTPRequestParser, NebulaHTTPServerError]
related: [[nebula-network-retry]], [[nebula-repository]], [[nebula-preferences]], [[nebula-aurora-swiftdata]], [[data-network-open-questions]]
status: shipped
shipped: "0.5.0"
---

# Nebula — Network architecture (Endpoint / Client / Request / Cache / Server)

> SHIPPED incrementally across Waves N5–N8 (Nebula 0.5.0). This note is the research + design record; the root docs (`ARCHITECTURE.md`, `DECISIONS.md`, `VERSIONING.md`) are the source of truth — root doc wins on conflict.

Wave N1 shipped a *thin* network surface (`NebulaHTTPGateway` with verb methods over `URLSession` + `NebulaRetry`) — no `Endpoint`/`Client`/`Request` abstraction, no per-endpoint cache, no server-side, and the research step was skipped. This cycle reworks the network layer into a proper Clean-Architecture surface, research-first.

## Owner decisions (2026-07-19)

- **Server side** = a simple local HTTP/1.1 server in Nebula via Network.framework (`NWListener`/`NWConnection`) — Foundation+Network, no third-party dep. Useful for integration tests and full-stack apps.
- **Cache** = a Nebula per-endpoint policy layer built **on top of** the native `URLCache` ("Ambos" — Nebula owns TTL/stale-while-revalidate metadata; the native `URLCache` holds the response bytes).

## Best-practice research (2025, no third-party deps)

The dominant pattern (Point-Free `APIClient`, Ben Cardy "A Swift API Client", dpearson2699 ios-networking skill, Stackademic 2025):

1. **`Endpoint` as a value type** with a `urlRequest(against:)` builder — the `URLRequestConvertible` idea. More flexible than an enum for parameterized endpoints.
2. **Protocol-based `HTTPClient`** with a generic `send<T: Decodable>(_ endpoint:, as: T.Type)`. The Point-Free shape — `send(_ endpoint:) -> Data` (or a response value) as the **one** transport requirement, decode as a **default extension** — is *existential-friendly*: `any HTTPClient` can call `send`. This matters for Nebula's port-based DI; the [[nebula-aurora-swiftdata]] work proved that `associatedtype`-returning methods **cannot** be called on `any` existentials under Swift 6.2. So `NebulaHTTPClient` is **non-generic** (no `associatedtype Response`).
3. **Verbs** (`get`/`post`/`put`/`delete`) are default-extension ergonomics on top of `send`, not the core contract.
4. **Test** with `URLProtocol`-backed `URLSession` (already the house pattern, `ArchitectureHTTPGatewayTests`) or a real local server (N7).
5. **Retry**: exponential + jitter, skip 4xx (except 408/429) and `CancellationError` — already shipped in `NebulaRetry` ([[nebula-network-retry]]).
6. **Don't** use Alamofire/Moya — native `URLSession` async/await closes the ergonomic gap (and Nebula is `dependencies: []`).

## Apple API ground truth (Xcode 27 Beta 3 `.swiftinterface`)

- `NWListener` — `final public class`, `: Sendable` (`Network.swiftinterface:718`); `init(using:on:) throws` (`on: NWEndpoint.Port = .any`); `newConnectionHandler` / `stateUpdateHandler` are `@preconcurrency … @Sendable`. Plain TCP via `NWParameters(tls: nil)`.
- `NWConnection` — `final public class`, `: Sendable` (`:2261`); **callback-based** `receive(minimumIncompleteLength:maximumLength:completion:)` and `send(content:contentContext:isComplete:completion:)` with `@escaping @Sendable` completions → wrap with `withCheckedThrowingContinuation` for async/await.
- `NWError` — `enum: Error, Equatable` (`.posix`/`.tls`/`.tcp`).
- `URLRequest.cachePolicy` get/set confirmed (`Foundation.swiftinterface:17395`); `URLRequest.CachePolicy` (`.useProtocolCachePolicy`/`.reloadIgnoringLocalCacheData`/`.returnCacheDataElseLoad`/…) and `URLCache` (`cachedResponse(for:)`/`storeCachedResponse(_:for:)`/`removeCachedResponse(for:)`/`init(memoryCapacity:diskCapacity:directory:)` at `:15653`) are ObjC-imported below-floor ungated Foundation.
- Network.framework (iOS 12 / macOS 10.14 / tvOS 12 / watchOS 5 / visionOS 1) and `URLCache` (iOS 8+) are both **below `.v26`** → **no `@available` gating** on any of this.

## Design (matches the house "port + config + façade" idiom)

`Sources/Nebula/Architecture/Network/`:

- `NebulaHTTPMethod` — `enum: String, Sendable` (get/post/put/patch/delete/head).
- `NebulaHTTPEndpoint` — the **port**: `protocol: Sendable { func urlRequest(against baseURL: URL?) throws -> URLRequest }` (non-generic, `URLRequestConvertible`); `cachePolicy` via a default extension (`.protocolDefault`), overridable by conformers.
- `NebulaHTTPRequest` — the concrete **value type** (`struct: NebulaHTTPEndpoint, Sendable, Equatable`): `method`/`path`/`query`/`headers`/`body: NebulaHTTPBody`/`cachePolicy`. `urlRequest(against:)` resolves the URL (relative→baseURL, absolute path, query appended not replaced — replicates the Wave N1 resolution so existing tests pass). `NebulaHTTPBody` is `enum: Sendable, Equatable { none, data(Data, contentType:), static func json(_:using:) throws }` — encodes **eagerly** so the value stays `Sendable` (the `Encodable` is consumed, not stored). **Reused as the server-side parsed-request type.**
- `NebulaHTTPResponse` — `struct: Sendable, Equatable { statusCode, headers: [String: String], body: Data }` + `decode<T: Decodable>(_:using:)`.
- `NebulaHTTPClient` — the **client port**: `protocol: NebulaGateway { func send(_ endpoint:) async throws -> NebulaHTTPResponse; var decoder: NebulaJSONDecoder; var encoder: NebulaJSONEncoder }`. Default extensions: `send<T: Decodable>(_:as:)` (decode) + the verb conveniences (`get`/`post`/`put`/`delete`) building a `NebulaHTTPRequest` and delegating to `send` — **preserving the Wave N1 verb signatures** so call sites are backward-compatible. The codec requirements let the verbs use the configured `NebulaJSONEncoder`/`Decoder` (configure-once-and-freeze preserved).
- `NebulaHTTPCachePolicy` — `enum: Sendable, Equatable { protocolDefault, bypass, store(ttl: Duration), staleWhileRevalidate(ttl: Duration, maxStale: Duration) }`.
- `NebulaHTTPCache` (N6) — the **cache port**: `response(for:policy:)`/`store(_:for:policy:)`/`remove(for:)`/`removeAll()`.
- `NebulaURLCache` (N6) — the **façade**: `final class` mirroring `NebulaDefaults` — `Mutex<(cache: URLCache, metadata: [Key: Entry])>` (one lock for the native `URLCache` + Nebula's TTL metadata), `init(_ cache: sending URLCache = .shared)`. Nebula owns TTL/freshness/SWR; the native `URLCache` holds the bytes.
- `NebulaHTTPServer` (N7) — `final class: Sendable` over `NWListener`; each `NWConnection` runs in a `Task` (async-wrapped `receive`/`send`). **Scope = "simple":** plain HTTP/1.1, no TLS, no chunked, no keep-alive (close after response), `Content-Length` body only. `NebulaHTTPRequestParser` (internal) + `NebulaHTTPServerError` (per-layer open struct `: NebulaFailure, Equatable, Hashable`, mirrors `NebulaRepositoryError`).

### Refactor of `NebulaHTTPGateway` (Wave H → N5)

`NebulaHTTPGateway` now conforms to `NebulaHTTPClient`. The verb methods move off the struct onto the `NebulaHTTPClient` default extension; the struct's one new requirement is `send(_:)`. `send`: `buildRequest` (endpoint → `URLRequest`, merge config headers for keys the request didn't set — **per-request headers override config defaults**; apply config `timeout`; map `cachePolicy` → `URLRequest.cachePolicy`) → `NebulaRetry.withPolicy` around `session.data(for:)` → `validate` (2xx) → `NebulaHTTPResponse`. Error bridging unchanged (`NebulaHTTPStatusError`/`URLError`/fallback → `NebulaError` kind `.network`, reported via `configuration.report(_:)`; no new `Kind` case). N6 adds an optional `cache: NebulaHTTPCache? = nil` constructor arg.

## Waves

- **N5 — DONE.** This note + `Network/` types (`NebulaHTTPMethod`/`NebulaHTTPEndpoint`/`NebulaHTTPRequest`/`NebulaHTTPBody`/`NebulaHTTPResponse`/`NebulaHTTPClient`) + `NebulaHTTPGateway` refactor (conforms to `NebulaHTTPClient`; verbs → default extension; `send(_:)` is core). Tests: `ArchitectureNetworkTests` + existing `ArchitectureHTTPGatewayTests` pass unchanged.
- **N6 — DONE.** `NebulaHTTPCachePolicy` + `NebulaHTTPCache` port (`NebulaCachedResponse` carries `isStale`) + `NebulaURLCache` façade (`Mutex<State>` over native `URLCache` + Nebula TTL metadata; `final class` derives `Sendable`, no `@unchecked`) + gateway `send` integration (fresh hit → skip network; stale → serve + `Task.detached` background revalidate; `.store`/`.staleWhileRevalidate` set `URLRequest.cachePolicy = .reloadIgnoringLocalCacheData` so Nebula's TTL wins over the native cache). Tests: `ArchitectureHTTPCacheTests` (10) + 5 gateway cache integration tests.
- **N7 — DONE.** `NebulaHTTPServer` (`final class: Sendable` over `NWListener`; each `NWConnection` runs in a `Task` with async-wrapped `receive`/`send`; `OnceFlag` `Mutex<Bool>` so `start()` resumes its continuation exactly once) + `NebulaHTTPRequestParser` (internal, bounded HTTP/1.1 — rejects negative/non-numeric/oversized `Content-Length`, 10 MiB body cap) + `NebulaHTTPServerError` (per-layer open struct `: NebulaFailure, Equatable, Hashable`, mirrors `NebulaRepositoryError`; `NWError` folded into the message — not boxed, lossy). Integration test `ArchitectureHTTPServerTests` (real localhost round-trip `NebulaHTTPServer` + `NebulaHTTPGateway` over `URLSession`, `@Suite(.serialized)`, OS-assigned ephemeral port — no `URLProtocol` stub). Adversarial review found one crash (negative `Content-Length` → reversed `Range` → trap) — fixed in the parser + two serializer hardenings (case-insensitive `Content-Length` overwrite, `\r\n` strip on handler headers).
- **N8 — DONE.** Governance (DocC `ArchitectureNetwork.md`/`ArchitectureHTTPCache.md`/`ArchitectureHTTPServer.md`, ADR in `DECISIONS.md`, CHANGELOG 0.5.0, ROADMAP Done section, `ARCHITECTURE.md` `Network/` subtree row + structure tree + prose) + final gate (`rm -rf .build && swift test` zero warnings, Aurora green, `swift build -c release`, per-platform `xcodebuild`, DocC `docbuild`) + tag 0.5.0. 635 Nebula tests / 127 suites green; zero concurrency warnings; release clean.

## Deferred (tracked, not this cycle)

Request middleware/interceptors (auth-token injection, 401 refresh-and-retry), streaming (`bytes(for:)`/SSE/WebSocket — Q4 deferred in [[data-network-open-questions]]), multipart upload, `download(for:)`-to-disk, pagination `AsyncSequence`. Later waves on request.
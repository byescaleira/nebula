---
tags: [padroes, architecture, network, auth, concurrency, nebula, actor]
aliases: [NebulaAuthInterceptor, NebulaHTTPInterceptor, NebulaTokenProvider, NebulaHTTPInterceptorChain, NebulaInterceptedClient, nebula auth interceptor, 401 refresh retry]
related: [[nebula-keychain-auth]], [[nebula-network-endpoint-client]], [[nebula-keychain]], [[nebula-network-retry]], [[nebula-app-readiness-research]]
status: shipped
shipped: "0.7.0 (Wave N10, 2026-07-20)"
---

# HTTP interceptors + 401 refresh-and-retry (Wave N10 — shipped)

The auth interceptor half of [[nebula-keychain-auth]] ([[nebula-app-readiness-research]] N10). A `Sendable` **interceptor port** (`NebulaHTTPInterceptor`) + a **chain** + a **token-provider port** (`NebulaTokenProvider`) + a concrete **`actor`** façade (`NebulaAuthInterceptor`) that does bearer injection and single-flight 401 refresh-and-retry, wired in via `NebulaHTTPClient.intercepted(by:)`. Source of truth = `Sources/Nebula/Architecture/Network/`; this note is synthesis. Full API verification + the pattern rationale live in [[nebula-keychain-auth]].

## The gap this fills

`NebulaRetry.withPolicy` (`NebulaRetry.swift:170-189`) re-invokes a captured `() async throws -> T` closure with **no input parameter** — it decides retry/no-retry via an `isRetriable` predicate but **cannot mutate the request between attempts**. So a 401 cannot trigger a token refresh + re-send with a new `Authorization` header through that seam. N10 adds a dedicated interceptor seam that can transform the endpoint before send and again before a retry.

## What shipped (Wave N10 / 0.7.0)

| Symbol | Path | Role |
|---|---|---|
| `NebulaHTTPInterceptor` | `Architecture/Network/NebulaHTTPInterceptor.swift` | The **port**: `adapt(_:) async throws -> NebulaHTTPEndpoint` (before send) + `retry(_:for:attempt:) async throws -> NebulaHTTPEndpoint?` (after a throw — return a fresh endpoint to retry with, `nil` to decline, throw to abort and surface that error). `: Sendable`. |
| `NebulaHTTPInterceptorChain` | same file | A `Sendable` struct holding `[any NebulaHTTPInterceptor]` (derived `Sendable`, NOT `Equatable`). Composes `adapt` left-to-right, sends once, and on failure offers each interceptor a **single** retry chance built from the **original** endpoint (no double-wrap). `CancellationError` is rethrown before the retry pass (never retried). `.withInterceptor(_:)` appends. |
| `NebulaInterceptedClient` | same file | A `Sendable` struct conforming to `NebulaHTTPClient`: holds the wrapped `client` + `chain`, forwards `decoder`/`encoder`, delegates `send` to `chain.send(_:through:)`. Derived `Sendable`, no `@unchecked`. |
| `NebulaHTTPClient.intercepted(by:)` | same file (default extension) | `intercepted(by chain:)` / `intercepted(by [any NebulaHTTPInterceptor])` → returns a `NebulaInterceptedClient`. The verbs (`get`/`post`/…) funnel through unchanged. |
| `NebulaTokenProvider` | `Architecture/Network/NebulaTokenProvider.swift` | The **port** the app conforms: `associatedtype Token: Sendable`; `currentToken() async throws -> Token?` (nil = anonymous passthrough); `refresh() async throws -> Token` (app-supplied error on failure); `authorizationHeader(for:) -> String` (e.g. `"Bearer <jwt>"`). PAT so the actor is generic over a concrete `Token`. |
| `NebulaAuthInterceptor<Provider>` | `Architecture/Network/NebulaAuthInterceptor.swift` | The concrete **`actor`** (Nebula's first). `adapt` injects `Authorization: Bearer <token>` (anonymous passthrough when `currentToken()` is nil); `retry` matches the 401 `NebulaError` at `attempt == 0`, refreshes **single-flight**, returns the endpoint re-adapted with the new token. Retry-once cap. |
| `_NebulaAuthAdaptingEndpoint` | same file (private) | A private `NebulaHTTPEndpoint` wrapper that sets `Authorization` on the built `URLRequest` and forwards `cachePolicy` from `base`. The header-injection mechanism. |

Tests: `ArchitectureAuthTests.swift` (15) — chain (empty forwards, adapt-once-per-send, `CancellationError` not retried, declined-retry surfaces original 500); `adapt` (injects `Bearer <current>`, nil-token anonymous passthrough, forwards `cachePolicy`); 401 (401-then-200 refreshes once + retries with `Bearer new-1` + sends==2, non-401 (500) not retried, second-401 surfaces with no infinite loop + refreshCount==1, refresh-failure surfaces `TestRefreshError` in place of the 401); concurrency `@Suite(.serialized)` (two concurrent 401s share **one** refresh — `refreshCount==1`, sends==4, both retries carry `Bearer new-1`; 50 concurrent always-200 → `refreshCount==0` all succeed); `intercepted` (verbs funnel the header through, two interceptors compose left-to-right). 677 Nebula tests / 136 suites green; zero concurrency warnings; release clean; all 5 platforms `xcodebuild` BUILD SUCCEEDED; DocC `BUILD DOCUMENTATION SUCCEEDED`.

## Design decisions

- **`NebulaAuthInterceptor` is an `actor` — Nebula's first.** CLAUDE.md: *"Actors, not global actors… use `actor` when shared mutable state spans many call sites and a single `Mutex` is awkward."* The interceptor owns the cached current token and a single in-flight refresh `Task`; concurrent 401s coordinate through it. An `actor` (mutable state isolated, implicit `Sendable`, no `@unchecked`) fits where a `Mutex` would be awkward (the `await`-based single-flight needs suspension, not just a lock). Zero actors existed in `Sources/Nebula/` before N10.
- **Single-flight via actor-isolated `Task<Token, any Error>?`.** `refresh()`: if `inFlight` is set, `await` it; else create a `Task { [provider] in try await provider.refresh() }`, store it, `defer { inFlight = nil }`, `await task.value`. The first 401 refreshes; concurrent 401s see the in-flight task and `await` it (exactly one `provider.refresh()`). The `await` suspends the actor (releasing it), so `adapt` calls aren't blocked during a refresh — only serialized on entry. On success `cachedToken` is updated; on failure the cache is cleared and the provider error surfaces.
- **Retry-once cap.** `attempt == 0` + the chain's single retry pass: a second 401 surfaces instead of looping forever. `CancellationError` short-circuits before the retry pass (mirrors `NebulaHTTPGateway`).
- **Header injection via `_NebulaAuthAdaptingEndpoint` (wrapper at the `URLRequest` layer).** Works because `NebulaHTTPGateway.buildRequest` (`NebulaHTTPGateway.swift:158-164`) routes through `endpoint.urlRequest(against:)` and only fills config headers for fields the endpoint did **not** set — so the injected `Authorization` is preserved. The retry re-injects from the **original** endpoint (the chain passes the original to `retry`), so no double-wrap of the stale header.
- **401 detection matches the gateway's bridge.** `isUnauthorized` tests `error as? NebulaError` with `code.domain == "Nebula.HTTP" && code.code == 401` — the exact `NebulaError` `NebulaHTTPGateway.send` surfaces (`NebulaHTTPGateway.swift:129-134`). 401 is NOT in `NebulaRetryPolicy.defaultIsRetriable` (only 408/429/500/502/503/504), so the gateway surfaces a 401 `NebulaError` immediately and the chain catches it. A non-401 `NebulaError` (5xx / `URLError`-bridged) does not match.
- **`NebulaTokenProvider` is a PAT** (not a generic method) so `NebulaAuthInterceptor` is generic over `Provider` and `Token` is concrete inside the actor. The app owns the conformer (reads tokens from [[nebula-keychain]] `NebulaKeychain`, refreshes against its auth backend); Nebula owns the coordination.
- **No new `NebulaError.Kind` — the interceptor is transparent.** It rethrows the client's errors; a refresh failure surfaces the app-supplied provider error in place of the 401 (better than the 401 that triggered it). `NebulaHTTPInterceptor.retry` throwing aborts the chain's retry pass and surfaces that error.
- **Sendable derivation across the surface** — `NebulaAuthInterceptor` is an `actor` (implicit `Sendable`); `NebulaHTTPInterceptorChain` / `NebulaInterceptedClient` derive `Sendable` from `Sendable` fields; `_NebulaAuthAdaptingEndpoint` derives `Sendable` from its `Sendable` base + `String`. No `@unchecked` authored anywhere.
- **`chain.send(_:through:)` is `internal`** — the public usage is `client.intercepted(by:)`; the chain's direct send is package-internal (tests route through `intercepted`, keeping the public surface lean).

## TDD fit (Wave N10)

- No network / no `URLProtocol`: a behavior-driven `SequenceClient: NebulaHTTPClient` (`final class` + `Mutex<State>`, `@Sendable (Int) -> Canned` where `Canned` is `.response` / `.httpStatus(Int)` (throws the `NebulaError` the gateway would surface) / `.cancellation`). Records the built `URLRequest`s and a send counter.
- `TestTokenProvider: NebulaTokenProvider` (`final class` + `Mutex`) with `Token = String`, configurable current token, a `refreshCount` counter, an optional `refreshDelay` (widen the single-flight window) and `refreshThrows`.
- The **single-flight test** is deterministic: a 15ms `refreshDelay` guarantees the first refresh is still in-flight when the second 401's retry enters `refresh()`; asserts `refreshCount == 1`, sends == 4, both retries carry the same `Bearer new-1`.
- The **retry-once cap** test (401-then-401) asserts the second 401 surfaces with `refreshCount == 1` and sends == 2 — no infinite loop.
- The **refresh-failure** test asserts the provider's `TestRefreshError` surfaces (not the 401), sends == 1 (the retry aborted at refresh).
- The concurrency suite is `@Suite(.serialized)` (timing-sensitive).

## Notes / guardrails

- Foundation-only — **no new framework import**, no `#if os()` (actor + interceptors are pure stdlib; 5-platform). `dependencies: []` stays pristine.
- The `"Nebula.HTTP"` string in `isUnauthorized` is the gateway's own domain constant (`NebulaHTTPGateway.swift:131`); a comment points there. Hoisting a public `NebulaError.Code`/domain constant is **deferred** (scope creep for v1).
- **Lean v0.7 surface**: retry count is fixed at 1 (retry-once); no configurable max-retry; no biometry (`LAContext` is `API_UNAVAILABLE(tvOS)` → deferred to a biometry wave); `SecAccessControlCreateWithFlags`-gated Keychain items deferred.
- No new `NebulaError.Kind` case (closed-enum rule).

## Build gate (Wave N10)

- Nebula: `rm -rf .build && swift build && swift test && swift build -c release` → 677 tests / 136 suites, zero warnings, release clean. 3× runs deterministic (single-flight/concurrency stable). No `#if os()` → per-platform risk nil; full 5-platform `xcodebuild` BUILD SUCCEEDED (iOS/macOS/tvOS/watchOS/visionOS). DocC `xcodebuild docbuild` → BUILD DOCUMENTATION SUCCEEDED (`ArchitectureAuth.md` resolves, `Architecture.md` link resolves).
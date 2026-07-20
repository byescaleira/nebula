---
tags: [padroes, architecture, network, retry, gateway, nebula]
aliases: [NebulaHTTPGateway, NebulaRetry, NebulaRetryPolicy, Nebula network layer, retry policy]
related: [[nebula-data-network-architecture]], [[nebula-repository]], [[nebula-errors]], [[data-network-open-questions]]
status: shipped
shipped: "2026-07-19 (Wave N1)"
---

# Network — NebulaHTTPGateway + NebulaRetry (Wave N1 — shipped)

The Foundation-only network half of the data+network surface ([[nebula-data-network-architecture]]). The concrete ``NebulaGateway`` over `URLSession` that the Wave H ``NebulaGatewayConfiguration`` scaffold was built for, plus a framework-agnostic retry primitive. Source of truth = `Sources/Nebula/Architecture/Gateway/NebulaHTTPGateway.swift` + `Sources/Nebula/Architecture/Async/NebulaRetry.swift`; this note is synthesis.

## What shipped (Wave N1)

| Symbol | Path | Role |
|---|---|---|
| `NebulaRetryJitter` | `Architecture/Async/NebulaRetry.swift` | `.none` / `.full` / `.equal` — the jitter strategy. |
| `NebulaRetryPolicy` | `Architecture/Async/NebulaRetry.swift` | `Sendable` value (NOT `Equatable` — stores a `@Sendable` `isRetriable` predicate, mirroring `NebulaGatewayConfiguration`): `maxAttempts` / `baseDelay` / `multiplier` / `maxDelay` / `jitter` / `isRetriable`. `delay(forFailedAttempt:)` = `baseDelay * multiplier^index`, capped at `maxDelay`, then jittered. `.with*` builders. `defaultIsRetriable` retries transient `URLError` codes (`.timedOut`/`.cannotConnectToHost`/`.networkConnectionLost`/`.notConnectedToInternet`/`.dnsLookupFailed`/`.cannotFindHost`) + HTTP 408/429/500/502/503/504. |
| `NebulaRetry.withPolicy(_:sleeper:operation:)` | `Architecture/Async/NebulaRetry.swift` | The retry loop for any `async throws`. Honors cancellation (`Task.checkCancellation()` before each attempt; a thrown `CancellationError` is never retried; a cancellation during `sleeper` propagates out). `sleeper` injectable for tests (default `Task.sleep(for:)`). Non-retriable errors surface on the first attempt, unwrapped (the original error, not wrapped). |
| `NebulaHTTPStatusError` | `Architecture/Gateway/NebulaHTTPGateway.swift` | `Error`/`Sendable`/`Equatable` carrying an HTTP status code — so the retry predicate distinguishes "transport failed" (`URLError`) from "server answered with an error status" and retries 5xx/408/429 selectively. |
| `NebulaHTTPGateway` | `Architecture/Gateway/NebulaHTTPGateway.swift` | Concrete `NebulaGateway` over `URLSession`. `get`/`post`/`put`/`delete` (decode `T` or raw `Data`); reuses `NebulaGatewayConfiguration`'s `NebulaJSONDecoder`/`NebulaJSONEncoder`; retries via `NebulaRetry.withPolicy`; bridges `URLError` + HTTP status → `NebulaError` (kind `.network`, code domain `Nebula.HTTP`/`NSURLErrorDomain`) and reports via the config's `handler`. `Sendable` derived (config + `URLSession` + policy all `Sendable` — no `@unchecked`). |

Tests: `ArchitectureRetryTests.swift` (16) + `ArchitectureHTTPGatewayTests.swift` (13) over a `URLProtocol`-backed `URLSession` (no real network). 557 Nebula tests / 113 suites green; zero concurrency warnings.

## Design decisions

- **Retry lives in `Architecture/Async/`, not `Gateway/`.** `NebulaRetry` is framework-agnostic (any `async throws` operation); HTTP is just its first consumer. Colocated with `NebulaResultPipeline` (async-flow helpers).
- **The retry predicate is `@Sendable (any Error) -> Bool`, not `(URLError) -> Bool`.** HTTP status codes aren't `URLError`s; a generic predicate lets the default retry 5xx/408/429 (via `NebulaHTTPStatusError`) alongside transport errors. `defaultIsRetriable` is a capture-free `static let` closure → trivially `Sendable`.
- **`NebulaRetryPolicy` is `Sendable` only, NOT `Equatable`** — the `@Sendable` predicate closure is not `Equatable` (mirrors `NebulaGatewayConfiguration` / `NebulaErrorConfiguration`). Document loudly.
- **`maxAttempts` = total attempts including the first** (`1` = no retry). Clamped to a minimum of `1` in `init`.
- **Cancellation is never retried.** `catch is CancellationError { throw }` before the generic catch, so even a predicate that returns `true` for everything cannot retry a `CancellationError`. A cancellation during `sleeper` (which throws `CancellationError` out of `Task.sleep`) propagates out of the loop.
- **Config errors fail fast before the retry loop.** `makeRequest` runs outside `NebulaRetry.withPolicy`, so a no-endpoint / unparseable-URL programmer error throws immediately (no retries, no `URLError` bridge) and surfaces as `NebulaError` kind `.unknown` (a misuse, not a transport failure). The retry loop only wraps the `URLSession.data(for:)` + `validate` call.
- **`NebulaHTTPStatusError` → `NebulaError` is built explicitly** (`code: .init(domain: "Nebula.HTTP", code: status.code), kind: .network, message: "HTTP \(code)"`) — NOT via `NebulaError(error:)` (which would map a plain Swift error to kind `.unknown`). No new `NebulaError.Kind` case is introduced (the closed-enum rule); `.network` already exists. `URLError` uses the existing `NebulaError(urlError:)` lossy mapping.
- **`Sendable` derived, no `@unchecked`.** `NebulaHTTPGateway` is a struct of three `Sendable` properties (`NebulaGatewayConfiguration` / `URLSession` / `NebulaRetryPolicy`). `URLSession` is `Sendable`; `URLRequest` is `Sendable` (captured in the retry closure). `NebulaRetryPolicy` is `Sendable` (all-`let` + a `@Sendable` closure).

## TDD fit (Wave N1)

- Retry math is pure: `policy.delay(forFailedAttempt: 0) == .milliseconds(100)` (`.none` jitter, exact); `.full`/`.equal` asserted in bounds over 64 samples.
- The retry loop is tested with an **instant sleeper** (`{ _ in }`) and a `final class Counter` (Mutex absorbed behind a copyable reference so the `~Copyable` `Mutex` can be captured in the `@Sendable` operation closure — the `NebulaSpyUseCase` precedent). Counting is deterministic: retries-until-success (3 calls), exhaustion (2 calls, `maxAttempts: 2`), non-retriable surfaces immediately (1 call), HTTP-503 retried, 404 not, `CancellationError` never retried, cancellation-during-sleep propagates, custom predicate decides.
- The gateway is tested over a `URLProtocol`-backed `URLSession` (`URLSessionConfiguration.ephemeral` + `protocolClasses`, no global registration). The suite is `@Suite(.serialized)` because the URLProtocol handler is process-wide shared state (Swift Testing runs parallel by default). A `SendableBox<T>` wraps the `~Copyable` `Mutex` so request/event capture closures stay `@Sendable`.
- `URLSession` moves `httpBody` → `httpBodyStream` for `URLProtocol`, so the captured request's `httpBody` is nil; the POST test asserts method/`Content-Type`/URL (body encoding is covered by `NebulaJSONEncoder`'s own tests).
- `URL(string:)` is lenient (accepts `"not a url"` as a relative URL); the config-error test uses `""` (one of the few inputs Foundation rejects) to actually hit the `noEndpointOrAbsoluteURL` branch.

## Notes / guardrails

- `URLSession` is Foundation → no new framework import, no binding-rule tension. The gateway ships in Nebula.
- Retry honors cancellation but the full `NebulaCancellation` / `NebulaError.wrapAsync` (Wave H decision #13) is still deferred — N1 uses a minimal `Task.checkCancellation()` + `CancellationError` check. Pulling `NebulaCancellation` forward is a later wave (see [[data-network-open-questions]] Q5).
- WebSocket / SSE / a higher-level "remote API client" are deferred (Q4) — `URLSessionWebSocketTask` is a different shape; ship when a second use earns it.
- One `NebulaHTTPGateway` per remote endpoint base; for multiple endpoints, instantiate per endpoint (the config's `endpoint` is optional so a single gateway can resolve per-request absolute URLs too).

## Build gate (Wave N1)

- Nebula: `rm -rf .build && swift build && swift test && swift build -c release` → 557 tests / 113 suites, zero warnings, release clean. New code has no `#if os()` (Foundation + Synchronization only) → per-platform risk nil; full 5-platform `xcodebuild` pass deferred to N4.
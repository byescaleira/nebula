# HTTP interceptors

A `Sendable` interceptor seam for cross-cutting request concerns, with a concrete `actor` that performs bearer-token injection and single-flight 401 refresh-and-retry.

## Overview

``NebulaRetry/withPolicy`` re-invokes a captured `() async throws -> T` closure
with no input parameter, so it cannot mutate the request between attempts — a
401 cannot trigger a token refresh and a re-send with a new `Authorization`
header through that seam. The interceptor port fills the gap.

``NebulaHTTPInterceptor`` is the **port**: two phases that mirror the classic
interceptor shape — ``NebulaHTTPInterceptor/adapt(_:)`` (runs before every send,
may transform the ``NebulaHTTPEndpoint``) and
``NebulaHTTPInterceptor/retry(_:for:attempt:)`` (runs after a send throws;
return a fresh endpoint to retry with, or `nil` to decline, or throw to abort
and surface that error). ``NebulaHTTPInterceptorChain`` composes interceptors
left-to-right, sends once, and on failure offers each interceptor a **single**
retry chance built from the **original** endpoint (so an interceptor that wraps
its input never double-wraps on retry). `CancellationError` is never retried.

```swift
let provider = AppTokenProvider(keychain: keychain)   // conforms to NebulaTokenProvider
let auth = NebulaAuthInterceptor(provider: provider)
let client = NebulaHTTPGateway(.init(endpoint: URL(string: "https://api.test")!))
let intercepted = client.intercepted(by: [auth])       // a NebulaHTTPClient

// Every send now carries `Authorization: Bearer <token>`; a 401 refreshes once
// (single-flight) and retries with the new token.
let body = try await intercepted.get("me")
```

``NebulaTokenProvider`` is the **port** the app conforms to supply credentials
(an `associatedtype Token: Sendable`): ``NebulaTokenProvider/currentToken()``
returns the current token or `nil` (anonymous passthrough),
``NebulaTokenProvider/refresh()`` obtains a fresh token (throwing an
app-supplied error on failure), and
``NebulaTokenProvider/authorizationHeader(for:)`` formats the header value
(`"Bearer <jwt>"`). The app reads tokens from ``NebulaKeychain`` and refreshes
against its auth backend; Nebula owns the coordination.

``NebulaAuthInterceptor`` is the concrete ``NebulaHTTPInterceptor`` — and
Nebula's first `actor`. ``NebulaAuthInterceptor/adapt(_:)`` injects
`Authorization: Bearer <token>` (anonymous passthrough when there is no
session); ``NebulaAuthInterceptor/retry(_:for:attempt:)`` matches the 401
``NebulaError`` that ``NebulaHTTPGateway`` surfaces (domain `"Nebula.HTTP"`,
code `401`) at `attempt == 0`, refreshes, and returns the endpoint re-adapted
with the new token. The header is injected at the `URLRequest` layer via a
private endpoint wrapper, which works because ``NebulaHTTPGateway`` only fills
config headers for fields the endpoint did not set.

The interceptor is **transparent**: it adds no ``NebulaError/Kind`` cases and
rethrows the client's errors. A refresh failure surfaces the app-supplied
provider error in place of the 401 (better than the 401 that triggered it).

### Why an `actor` (single-flight refresh)

CLAUDE.md: *"Actors, not global actors… use `actor` when shared mutable state
spans many call sites and a single `Mutex` is awkward."* The interceptor owns
the cached current token and a single in-flight refresh `Task`; when several
concurrent requests hit a 401, only the first triggers
``NebulaTokenProvider/refresh()`` and the rest `await` the same task — avoiding
N parallel refreshes against the auth backend. The first 401 creates a `Task`,
stores it, and `await`s its value (suspending → releasing the actor); a
concurrent 401 sees the in-flight task and `await`s it. The slot is cleared on
completion; a caller that already captured the task reference still receives its
result. The actor's mutable state is isolated (no `@unchecked`); the actor is
implicitly `Sendable`. Retry is capped at **once** (`attempt == 0` plus the
chain's single retry pass), so a second 401 surfaces instead of looping.

## Topics

### Port
- ``NebulaHTTPInterceptor``
- ``NebulaHTTPInterceptor/adapt(_:)``
- ``NebulaHTTPInterceptor/retry(_:for:attempt:)``

### Chain & composed client
- ``NebulaHTTPInterceptorChain``
- ``NebulaHTTPInterceptorChain/withInterceptor(_:)``
- ``NebulaInterceptedClient``
- ``NebulaHTTPClient/intercepted(by:)``

### Token provider
- ``NebulaTokenProvider``
- ``NebulaTokenProvider/currentToken()``
- ``NebulaTokenProvider/refresh()``
- ``NebulaTokenProvider/authorizationHeader(for:)``

### Concrete façade
- ``NebulaAuthInterceptor``
- ``NebulaAuthInterceptor/init(provider:)``
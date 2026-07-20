# HTTP Cache

The per-endpoint cache port and the concrete façade over the native `URLCache`.

## Overview

Nebula owns the per-endpoint cache **policy** — TTL and stale-while-revalidate metadata — built **on top of** the native `URLCache`, which holds the response bytes ("Ambos — Nebula sobre nativo"). The gateway consults the cache only for ``NebulaHTTPCachePolicy/store(ttl:)`` and ``NebulaHTTPCachePolicy/staleWhileRevalidate(ttl:maxStale:)``; ``NebulaHTTPCachePolicy/protocolDefault`` delegates to `URLSession`'s native HTTP cache and ``NebulaHTTPCachePolicy/bypass`` skips caching entirely. When a Nebula cache is injected, the gateway sets `URLRequest.cachePolicy = .reloadIgnoringLocalCacheData` for the Nebula-managed policies so Nebula's TTL wins over the native cache.

``NebulaHTTPCache`` is the `Sendable` port: `response(for:policy:)` returns a ``NebulaCachedResponse`` (a response paired with `isStale`) or `nil`; `store(_:for:policy:)`, `remove(for:)`, `removeAll()`. The `isStale` flag lets the gateway serve a stale hit immediately and revalidate in a background `Task.detached` (so a `@MainActor` consumer does not get the store hopping to main). ``NebulaURLCache`` is the concrete façade: a `final class` wrapping `Mutex<State>` (the native `URLCache` plus Nebula's metadata map). `URLCache` is thread-safe but not `Sendable` in Swift 6 (verified against the Xcode 27 Beta 3 `.swiftinterface`), so the `Mutex` provides the synchronization boundary and the `final class` derives `Sendable` with **no `@unchecked`** — the ``NebulaDefaults`` precedent. Inject a test double by conforming to ``NebulaHTTPCache``.

```swift
let cache = NebulaURLCache(URLCache(memoryCapacity: 4_000_000, diskCapacity: 0))
let cfg = NebulaGatewayConfiguration.default
    .withEndpoint(URL(string: "https://api.acme.com")!)
    .withCache(cache)
let gateway = NebulaHTTPGateway(configuration: cfg, retryPolicy: .init(maxAttempts: 3))
```

## Topics

### Policy
- ``NebulaHTTPCachePolicy``

### Port + façade
- ``NebulaHTTPCache``
- ``NebulaCachedResponse``
- ``NebulaURLCache``
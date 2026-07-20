# Network

The Endpoint / Client / Request / Response model — the Clean-Architecture network surface the concrete gateway conforms to.

## Overview

Wave N1 shipped a *thin* network surface (a concrete ``NebulaHTTPGateway`` with verb methods over `URLSession`). Waves N5–N8 rework it into a proper Clean-Architecture surface, research-first: an `Endpoint` value type, a protocol-based `Client`, and a `Request`/`Response` pair — all in `Sources/Nebula/Architecture/Network/`. The design is existential-friendly (the Point-Free `send(_:) -> Response` shape): ``NebulaHTTPClient`` is **non-generic** so `any NebulaHTTPClient` can call `send` — the [[nebula-aurora-swiftdata]] work proved `associatedtype`-returning methods cannot be called on `any` existentials under Swift 6.2. The verbs (`get`/`post`/`put`/`delete`) are **default extensions** on top of `send`, preserving the Wave N1 signatures so call sites are backward-compatible.

``NebulaHTTPEndpoint`` is the port — a `Sendable` type that builds a `URLRequest` against a base URL (the `URLRequestConvertible` idea). ``NebulaHTTPRequest`` is the concrete value type (method / path / query / headers / body / cache policy) and is **reused as the server-side parsed-request type**, so the client and the local server share one request shape. ``NebulaHTTPBody`` (`.none` / `.data(_:contentType:)` / `.json(_:using:)`) encodes **eagerly** so the value stays `Sendable` — the `Encodable` is consumed, not stored. ``NebulaHTTPResponse`` carries a status code, headers, body, and a generic `decode(_:using:)`. ``NebulaHTTPClient`` refines ``NebulaGateway`` with `send(_:) async throws -> NebulaHTTPResponse` plus the decode + verb conveniences.

```swift
struct OrdersEndpoint: NebulaHTTPEndpoint {
    func urlRequest(against baseURL: URL?) throws -> URLRequest {
        NebulaHTTPRequest(method: .get, path: "orders/\(id)").urlRequest(against: baseURL)
    }
}
let order: Order = try await client.send(OrdersEndpoint(), as: Order.self)
// Or the verb convenience (delegates to send):
let order: Order = try await client.get(Order.self, "orders/\(id)")
```

## Topics

### Endpoint + Request
- ``NebulaHTTPEndpoint``
- ``NebulaHTTPRequest``
- ``NebulaHTTPBody``
- ``NebulaHTTPMethod``

### Response
- ``NebulaHTTPResponse``

### Client port
- ``NebulaHTTPClient``
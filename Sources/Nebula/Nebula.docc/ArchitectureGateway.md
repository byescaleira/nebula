# Gateway

The gateway marker, its configuration, and the concrete HTTP gateway over `URLSession`.

## Overview

Nebula ships the seam **and** a concrete Foundation-only HTTP adapter. ``NebulaGateway`` is the bare `Sendable` marker; ``NebulaGatewayConfiguration`` is the configure-once-and-freeze value (it reuses the existing ``NebulaJSONDecoder``/``NebulaJSONEncoder`` — no duplicated Codable plumbing — and mirrors ``NebulaErrorConfiguration``: a `Sendable` struct, NOT `Equatable` because it stores a `@Sendable` handler, with fluent `.with*` builders and a ``NebulaGatewayConfig`` process-wide `Mutex` accessor). ``NebulaHTTPGateway`` is the concrete gateway over `URLSession` that this scaffold was built for (Wave N1): `get`/`post`/`put`/`delete`, retries via ``NebulaRetry`` (see <doc:ArchitectureAsync>), and bridges `URLError` / HTTP status failures to ``NebulaError`` (kind `.network`) reported through the config's `handler`.

```swift
let cfg = NebulaGatewayConfiguration.default
    .withEndpoint(URL(string: "https://api.acme.com")!)
    .withTimeout(.seconds(30))
NebulaGatewayConfig.set(cfg)

let gateway = NebulaHTTPGateway(configuration: cfg, retryPolicy: .init(maxAttempts: 3))
let order: Order = try await gateway.get(Order.self, "orders/\(id)")
```

## Topics

### Marker
- ``NebulaGateway``

### Configuration
- ``NebulaGatewayConfiguration``
- ``NebulaGatewayConfig``

### Concrete HTTP gateway
- ``NebulaHTTPGateway``
- ``NebulaHTTPStatusError``
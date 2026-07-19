# Gateway

The gateway marker and its configuration — the seam an app's concrete gateway (e.g. URLSession) implements.

## Overview

Nebula ships **only the seam**: a ``NebulaGateway`` marker protocol and a ``NebulaGatewayConfiguration`` value. The concrete HTTP gateway lives in the app (URLSession) — an `NebulaHTTPGateway` was deferred to keep v1 surface small (decision #8). The configuration reuses the existing ``NebulaJSONDecoder``/``NebulaJSONEncoder`` (it does not duplicate Codable plumbing) and mirrors ``NebulaErrorConfiguration``: a `Sendable` struct (NOT `Equatable` — it stores a `@Sendable` handler) with fluent `.with*` builders, a `report(_:)` gated on `isEnabled`, and a ``NebulaGatewayConfig`` process-wide `Mutex` accessor.

```swift
let cfg = NebulaGatewayConfiguration.default
    .withEndpoint(URL(string: "https://api.acme.com")!)
    .withTimeout(.seconds(30))
NebulaGatewayConfig.set(cfg)
```

## Topics

### Marker
- ``NebulaGateway``

### Configuration
- ``NebulaGatewayConfiguration``
- ``NebulaGatewayConfig``
# HTTP Server

A simple local HTTP/1.1 server over Network.framework — the server-side counterpart to ``NebulaHTTPGateway``.

## Overview

``NebulaHTTPServer`` is a `final class: Sendable` over `NWListener` / `NWConnection` (Network.framework — Foundation + Network, no SwiftUI / UIKit / new framework import). It listens on a TCP port, accepts connections, parses each request via the internal ``NebulaHTTPRequestParser`` into a ``NebulaHTTPRequest`` (the same value type the client builds), dispatches it to a `@Sendable` handler, and writes the handler's ``NebulaHTTPResponse`` back as HTTP/1.1 bytes. Each connection runs in a `Task` (the callback-based `receive` / `send` are async-wrapped via `withCheckedContinuation`) and is closed after one response. `Sendable` is derived — `NWListener`, `NWConnection`, the `@Sendable` handler, and `DispatchQueue` are all `Sendable` at the `.v26` floor (no `@unchecked`); the one shared mutable state (the start-once flag) is a `Mutex`-guarded `final class`.

Scope is deliberately **"simple"**: plain HTTP/1.1, no TLS, no chunked transfer-encoding, no keep-alive (close after one response), `Content-Length` bodies only. A dev / test / full-stack-app tool, not a production server. The parser is bounded — it rejects negative, non-numeric, and oversized (`> 10 MiB`) `Content-Length` up front (a negative value would otherwise build a reversed `Range` and trap the process), and the serializer strips `\r\n` from handler-provided headers and overwrites any handler `Content-Length` (case-insensitive) with the actual body count. ``NebulaHTTPServerError`` is the per-layer open struct (`: NebulaFailure, Equatable, Hashable`, mirroring ``NebulaRepositoryError``) bridging to ``NebulaError`` via `toNebulaError(kind:)`; `NWError` is not `Sendable`, so it is folded into the message (lossy, mirroring the gateway's `URLError` bridging).

```swift
let server = try NebulaHTTPServer(port: 8080) { request in
    NebulaHTTPResponse(statusCode: 200, body: Data("hello".utf8))
}
try await server.start()
// ... requests are served on the cooperative pool ...
server.stop()
```

## Topics

### Server
- ``NebulaHTTPServer``
- ``NebulaHTTPRequestParser``
- ``NebulaHTTPServerError``
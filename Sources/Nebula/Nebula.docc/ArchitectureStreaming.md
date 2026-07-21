# Streaming (SSE + WebSocket)

Two **additive** streaming surfaces on top of the existing buffered HTTP gateway: Server-Sent Events over `URLSession.bytes(for:)` and a WebSocket port + façade over `URLSessionWebSocketTask` — with **zero gateway changes**. Both reuse the N17a pinning session for transport-layer TLS pinning.

## Overview

``NebulaHTTPGateway.send`` returns a buffered ``NebulaHTTPResponse`` with `body: Data` (verified; there is no streaming method on ``NebulaHTTPClient``). N17b adds two **additive** streaming surfaces that do not touch the gateway:

- **SSE** — ``NebulaSSEEventStream/events(for:session:configuration:)`` parses a Server-Sent Events stream over `URLSession.bytes(for:)` and yields ``NebulaSSEEvent``s through an `AsyncThrowingStream` (the CLAUDE.md-mandated concrete return type). Includes spec-compliant auto-reconnect with `Last-Event-ID`.
- **WebSocket** — a ``NebulaWebSocketClient`` **port** (the Nebula ports-and-adapters idiom, mirroring ``NebulaHTTPClient``) + a ``NebulaURLSessionWebSocket`` concrete façade over `URLSessionWebSocketTask` + a combined ``NebulaWebSocketSessionDelegate`` (pinning + WebSocket lifecycle) + a ``NebulaWebSocketSession/pinned(by:)`` builder.

```swift
// SSE: pass a pinned session for transport-layer pinning.
let stream = NebulaSSEEventStream.events(
    for: URLRequest(url: URL(string: "https://api.example.com/events")!),
    session: pinned.session)

// WebSocket: the ergonomic entry point.
let ws = NebulaWebSocketSession.open(
    url: URL(string: "wss://api.example.com/events")!,
    using: NebulaWebSocketSession.pinned(by: policy))
```

Pinning rides the `URLSession`'s delegate: the auth-challenge method is on `URLSessionDelegate`, which `URLSessionWebSocketDelegate` inherits — so the **same** session delegate handles both HTTP(SSE) and WebSocket pinning.

## SSE

``NebulaSSEEventStream/events(for:session:configuration:)`` returns an `AsyncThrowingStream<NebulaSSEEvent, any Error>` — the CLAUDE.md-mandated concrete return type (a `some AsyncSequence` return is illegal in a protocol requirement and this stream is returned from a `static func`). Internally it iterates the **raw `URLSession.AsyncBytes` byte stream** and forms lines manually — **NOT `.lines`**: `AsyncLineSequence` skips empty lines, but SSE dispatches on the **blank line**, so `.lines` would drop every dispatch boundary. A `\n` (0x0A) ends a line; an empty buffer at `\n` is the blank line that triggers dispatch (a `\r\n` pair is handled by the parser's defensive `\r` strip).

### Parser

``NebulaSSEParser`` is an `internal` pure WHATWG-spec state machine (the testable seam): feed it lines and it returns a fully-formed ``NebulaSSEEvent`` on a blank-line dispatch (when the `data` buffer is non-empty), `nil` otherwise. It holds no I/O and no `@Sendable` closure — pure, so it is unit-tested directly with canned `[String]`. WHATWG rules implemented:

- A line starting with `:` is a comment (ignored).
- `field: value` splits on the first colon; one leading space after the colon is stripped (per spec).
- A line without a colon is a field with an empty value.
- `event` sets the type; `data` appends `value + "\n"`; `id` sets the last event ID (rejected if the value contains U+0000 NULL); `retry` parses a non-negative integer (lossy: non-int values ignored); unknown fields are ignored.
- A blank line dispatches (when `data` is non-empty), resetting the `data`/`event` buffers while **preserving** `lastEventID` and `retry` across dispatches (per spec). A deliberate, documented deviation: a pure-control blank line (only `id:`/`event:`/`retry:` set, no `data:`) does **not** yield a spurious empty event (heartbeats are `:` comments, not blank lines).

### Reconnect

The reconnect loop is **custom** (NOT ``NebulaRetry/withPolicy``): the request mutates per attempt (the `Last-Event-ID` header advances with the cursor), and `withPolicy`'s `operation` is a nullary closure that cannot mutate the request between attempts. The loop mirrors `withPolicy`'s cancellation contract — cancellation is honored immediately and **never retried**. On a clean stream end or a recoverable error it reconnects (when configured), sending the cursor's `Last-Event-ID` header.

### Cancellation semantics

When the consumer stops iterating (cancels its `Task` or the stream finishes), `onTermination` cancels the internal loop so the `bytes(for:)` task is torn down — the consumer's `for try await` ends **normally** on cancellation (an `AsyncThrowingStream` does **not** throw `CancellationError` to its consumer; `Iterator.next()` returns `nil`). The internal `finish(throwing: CancellationError())` exists to tear the internal `bytes(for:)` task down cleanly via `onTermination → loop.cancel()` — it is a no-op for a consumer that has already stopped.

## WebSocket

``NebulaURLSessionWebSocket`` is a `final class` façade over `URLSessionWebSocketTask` (which is annotated `NS_SWIFT_SENDABLE` — `NSURLSession.h:1121`, correcting the prior research note). `Sendable` is **derived** from the `let` stored props (the pinned session, the task, an optional logger) — **no `@unchecked`**. The façade holds the ``NebulaPinnedWebSocketSession`` (session + delegate) so the delegate is not silently dropped (`URLSession` does **not** strongly retain its delegate) — retaining the façade retains everything.

``NebulaWebSocketMessage`` mirrors `URLSessionWebSocketTask.Message` (`case data(Data)` / `case string(String)`) as a Nebula-owned type — the idiom is never to expose Apple's nested enum in a Nebula port. The `init(_:)` is **failable** because `URLSessionWebSocketTask.Message` is a non-frozen enum: an unknown future case yields `nil` (the façade surfaces it as a ``NebulaWebSocketError/unknown``), with `@unknown default` so the switch stays future-proof.

### Delegate

``NebulaWebSocketSessionDelegate`` is a `final class : NSObject, URLSessionWebSocketDelegate, Sendable` — ONE object per session that does SSL/TLS pinning (via **composition** with the N17a ``NebulaURLSessionDelegate``) AND surfaces the WebSocket lifecycle (`didOpenWithProtocol` / `didCloseWith`). `Sendable` is **derived** (all stored props are immutable `let`s of Sendable type; `URLSessionWebSocketDelegate` is an `@objc` protocol NOT annotated `NS_SWIFT_SENDABLE`, but conformance to a non-Sendable `@objc` protocol does not block derived `Sendable` on a `final class` with all-`let` Sendable props — the ``NebulaUNNotificationCenter`` analogy). Probed against the Xcode 27 Beta 3 SDK → EXIT=0. **No `@unchecked`.**

The auth-challenge method **forwards** to the held ``NebulaURLSessionDelegate`` — `pinningDelegate.urlSession(…)` is `public` and callable directly. **Zero N17a source change, zero pinning-logic duplication.** No `import Security` here — the `Sec*` evaluation lives in the N17a delegate; this class only forwards the call.

### Session builder

``NebulaWebSocketSession/pinned(by:configuration:logger:onOpen:onClose:)`` returns a ``NebulaPinnedWebSocketSession`` carrying both the `URLSession` and the delegate (the caller must retain both — the `URLSession`-does-not-retain-its-delegate footgun, same as ``NebulaPinnedSession``). ``NebulaWebSocketSession/open(url:protocols:using:logger:)`` is the ergonomic entry: it creates the task via `URLSession.webSocketTask(with:)`, `.resume()`s it, and returns the façade. `URLSessionWebSocketTask`'s `init`/`new` is unavailable, so the façade cannot create the task itself — the session builder owns task creation.

## Errors

``NebulaSSEError`` and ``NebulaWebSocketError`` are open-struct errors mirroring ``NebulaHTTPServerError`` / ``NebulaSSLPinningError``: an extensible ``NebulaSSEError/Kind`` / ``NebulaWebSocketError/Kind`` (a string literal — new categories need no library release) plus the coarse ``NebulaError/Kind`` mapping and the `toNebulaError(kind:)` bridge. **No new ``NebulaError/Kind`` case** is added (the closed envelope stays closed). ``NebulaWebSocketError/closed(code:reason:)`` carries the close code in metadata + the reason in the message.

## Sendability

All N17b types are below the `.v26` floor on every platform (`URLSession.bytes(for:)` is macOS 12 / iOS 15 / watchOS 8 / tvOS 15 / visionOS 1.0+; `URLSessionWebSocketTask` / `URLSessionWebSocketDelegate` are macOS 10.15 / iOS 13 / watchOS 6 / tvOS 13 / visionOS 1.0+) — **no `@available` gate** anywhere in N17b. `URLSessionWebSocketTask` is `NS_SWIFT_SENDABLE`; `NebulaWebSocketSessionDelegate` and `NebulaURLSessionWebSocket` derive `Sendable` via the `NebulaUNNotificationCenter` analogy; all public value types derive `Sendable` from value-type fields. **No `@unchecked` on any value type.** `NebulaSSEConfiguration` is `Sendable` but **NOT `Equatable`** (the `@Sendable` sleeper — mirroring ``NebulaLogConfiguration``'s not-`Equatable` handler flavor).

## Testability note

The asymmetry: SSE is exercised via a `URLProtocol`-backed `URLSession` (`URLProtocol` intercepts `URLSession.bytes(for:)` data tasks); WebSocket is exercised via an `NWListener` WebSocket echo server (`URLProtocol` does **not** intercept `URLSessionWebSocketTask`, so the live round-trip needs a real listener — `Network.framework` is admissible, the ``NebulaHTTPServer`` precedent). The pure logic — the ``NebulaSSEParser``, the message bridge, the error mapping, the delegate lifecycle + auth-challenge forwarding, the session builder — is unit-tested without a live socket. The echo server handles the client handshake via `NWProtocolWebSocket.Options.setClientRequestHandler` + `autoReplyPing` and echoes each message with the same opcode (the echo `send` carries `NWProtocolWebSocket.Metadata` so the frame is valid).

## Topics

### SSE
- ``NebulaSSEEventStream``
- ``NebulaSSEEventStream/events(for:session:configuration:)``
- ``NebulaSSEEvent``
- ``NebulaSSEConfiguration``
- ``NebulaSSEConfiguration/default``
- ``NebulaSSEConfiguration/withReconnect(_:)``
- ``NebulaSSEConfiguration/withMaxReconnectAttempts(_:)``
- ``NebulaSSEConfiguration/withReconnectDelay(_:)``
- ``NebulaSSEConfiguration/withSleeper(_:)``

### WebSocket
- ``NebulaWebSocketClient``
- ``NebulaWebSocketMessage``
- ``NebulaWebSocketMessage/init(_:)``
- ``NebulaWebSocketMessage/rawMessage``
- ``NebulaURLSessionWebSocket``
- ``NebulaWebSocketSessionDelegate``
- ``NebulaWebSocketSession``
- ``NebulaWebSocketSession/pinned(by:configuration:logger:onOpen:onClose:)``
- ``NebulaWebSocketSession/open(url:protocols:using:logger:)``
- ``NebulaWebSocketSession/open(request:using:logger:)``
- ``NebulaPinnedWebSocketSession``

### Errors
- ``NebulaSSEError``
- ``NebulaSSEError/Kind``
- ``NebulaSSEError/coarseKind``
- ``NebulaSSEError/toNebulaError(kind:)``
- ``NebulaWebSocketError``
- ``NebulaWebSocketError/Kind``
- ``NebulaWebSocketError/coarseKind``
- ``NebulaWebSocketError/toNebulaError(kind:)``

<!-- Copyright (c) 2026 Nebula. All rights reserved. -->
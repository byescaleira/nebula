# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.16.0] - 2026-07-21

> Nebula 0.16.0 — aligned to OS 26 (Liquid Glass). **Bodies & downloads:** the network-hardening Wave N17c — the **third and final sub-wave of the N17 split** (N17a pinning → N17b streaming → N17c bodies/downloads). Three **additive** surfaces on top of the existing buffered HTTP gateway — the gateway is **unchanged** (`NebulaHTTPGateway`/`NebulaHTTPClient`/`NebulaHTTPBody`/`NebulaHTTPRequest`/`NebulaHTTPRequestParser` diffs empty), and the N17a pinning is **reused via composition** (zero N17a source change, no `import Security` in the product target).
>
> **Multipart — `NebulaMultipartBuilder`, a pure `multipart/form-data` (RFC 2388) `Data` composer.** Foundation has NO multipart API (a full grep of `Foundation.swiftinterface` returns zero hits) — this is genuinely new app-layer code, not a wrapper. `NebulaMultipartPart` (field/file) is assembled under a random boundary (16 random bytes hex-encoded under `"----NebulaBoundary"` — within RFC 2046 §5.1.1's 0–70-char limit; **no `import CryptoKit`** — multipart doesn't hash). `build()` is pure (no `URLSession`, no `@Sendable` closure, no I/O except the explicit `file(in:)` temp-file writer for `URLSession.upload(for:fromFile:)` — streaming from disk, suitable for large/background uploads). **Gateway-compatible by design**: the built `Data` + content-type feed the existing `NebulaHTTPBody.data(_:contentType:)` — **no new `NebulaHTTPBody` case**, no `NebulaHTTPRequest`/parser ripple.
>
> **Download — `NebulaDownload.download(for:session:configuration:)` → `NebulaDownloadHandle`.** A façade over `URLSession.download(for:delegate:)` (a temp-file URL deleted on return — the façade moves it via a caller-supplied `destination` closure). The handle exposes `progress: AsyncThrowingStream<Double, any Error>` (fraction 0.0–1.0, bridged from the `URLSessionDownloadDelegate.didWriteData` callback — Foundation has NO async `for await` progress API, verified) and `value() async throws -> URL` (the moved destination). `cancelByProducingResumeData()` wraps the completion-handler-only `URLSessionDownloadTask.cancel(byProducingResumeData:)` in a `withCheckedContinuation` (no async form exists; the task is captured in the delegate since the async overlay does not expose it). The retry-with-resume loop is **custom, NOT `NebulaRetry.withPolicy`** — the resume `Data` mutates the attempt (`download(resumeFrom:)`), and `withPolicy`'s `operation` is nullary (the SSE `Last-Event-ID` precedent); failure-path resume reads `URLError.downloadTaskResumeData`. `NebulaDownloadDelegate` is a `final class : NSObject, URLSessionDownloadDelegate, Sendable` — `Sendable` is **derived** (all stored props are `let`s of Sendable type; `URLSessionDownloadDelegate` is an `@objc` protocol NOT `NS_SWIFT_SENDABLE`, but conformance does NOT block derived `Sendable` on a `final class` with all-`let` Sendable props — the N17b analogy; probed against the Xcode 27 Beta 3 SDK with `swiftc -typecheck -swift-version 6 -strict-concurrency=complete -warnings-as-errors` → EXIT=0; **no `@unchecked`**). `NebulaDownloadConfiguration` is per-call, `Sendable` but NOT `Equatable` (the `@Sendable` closures — the `NebulaSSEConfiguration` flavor); no `Mutex` accessor, `Nebula.md` config list unchanged.
>
> **Two load-bearing design decisions.** (1) **Delegate routing** — the per-task `delegate:` passed to `download(for:delegate:)` receives the `URLSessionDownloadDelegate` callbacks (`didFinishDownloadingTo`/`didWriteData`/`didCompleteWithError`); SSL/TLS pinning rides the **session** delegate (the server-trust auth challenge is a session-level `URLSessionDelegate` method). So `NebulaDownloadDelegate` holds NO pinning — `NebulaDownload.pinned(by:sessionConfiguration:configuration:logger:)` sets the N17a `NebulaURLSessionDelegate` as the session delegate. **Zero N17a source change, zero pinning-logic duplication, no `import Security` in the product target.** (2) **Consumer cancellation** surfaces via the **loop** (it resumes the completion box with `CancellationError` from `Task.checkCancellation()` / the `URLError(.cancelled)` branch), NOT via `withCheckedThrowingContinuation` auto-cancellation — which does NOT throw on Task cancel without a `withTaskCancellationHandler` bridge. The consumer's `for try await` over `progress` ends normally on cancel (the N17b semantics); `value()` throws `CancellationError`.
>
> **Pagination — `NebulaPagedSequence<Page: Sendable>`.** A generic `Sendable` helper returning `AsyncThrowingStream<Page, any Error>` (the CLAUDE.md-mandated concrete return). `first`/`next` `@Sendable` closures decouple cursor transport (the app's concern — URL query item, header, or body token) from the loop (Nebula's concern), stopping when `next` returns `nil`. Custom loop, NOT `NebulaRetry.withPolicy` (the cursor mutates per page — the SSE `Last-Event-ID` shape); no retry (pagination surfaces a failed page's error). `Sendable` is derived (constrain `<Page: Sendable>` at the declaration, the `NebulaResultPipeline<T: Sendable>` precedent; no `@unchecked`).
>
> **Sendability — all N17c symbols below the `.v26` floor → no `@available` gate anywhere.** `URLSession.upload(for:fromFile:)` / `URLSession.download(for:delegate:)` (macOS 12/iOS 15/watchOS 8/tvOS 15/visionOS 1.0+), `URLError.downloadTaskResumeData` (macOS 10.15/iOS 13/watchOS 6/tvOS 13), `cancel(byProducingResumeData:)` (macOS 10.9/iOS 7/watchOS 2/tvOS 9), `URLComponents`/`URLQueryItem` (far below). `URLSession`/`URLSessionDownloadTask`/`Progress`/`URLComponents`/`URLQueryItem` are `NS_SWIFT_SENDABLE` (verified against `NSURLSession.h`/`NSProgress.h`/`.swiftinterface`). `NebulaDownloadDelegate` derives `Sendable`; all public value types derive `Sendable` from value-type fields. **Zero `@unchecked` on any type** (N17c adds none — the delegate derives). `import Foundation` + `import Synchronization` only; no `import Security` (pinning forwarded), no `import CryptoKit`, no `import Network` (downloads use `URLSession`). `NebulaMultipartError`/`NebulaDownloadError` are open-struct errors mirroring `NebulaSSEError` (no new `NebulaError.Kind` case; `coarseKind` maps `.network`/`.unknown`).
>
> **Testability stance (documented limitation).** A `URLProtocol`-backed live round-trip over the async `URLSession.download(for:delegate:)` temp-file path **hangs** — `URLProtocol` does not cleanly bridge the async download overlay's temp-file + `didFinishDownloadingTo` dispatch (the overlay never completes). This mirrors the N17a pragmatic stance: a transport seam that is not injectable from a unit test is documented rather than forced. The pure logic (multipart builder + temp-file writer + error mapping, pagination loop + cancellation + error propagation, download error/resume-data extraction seams, delegate lifecycle, race-safe completion box) is unit-tested without a live socket; the live round-trip is a compile-only guarantee (the façade builds on all 5 platforms; move-to-destination + progress + resume behavior verified at the delegate/loop seams). Ships as Nebula 0.16.0 (additive minor within Nebula 26 — new public types; no breaking change). **N17 split complete.** Tagging deferred to the owner's gate decision. 908 tests / 178 suites.

### Added — Wave N17c (Bodies & downloads)
- ``NebulaMultipartBuilder`` — pure `multipart/form-data` (RFC 2388) `Data` composer; auto-generated boundary; `adding(_:)` fluent; `build()` pure; `file(in:)` temp-file writer for `URLSession.upload(for:fromFile:)`.
- ``NebulaMultipartPart`` / ``NebulaMultipartFormData`` — `Sendable`/`Equatable`/`Hashable` value types; `.field`/`.file` factory statics.
- ``NebulaDownload`` — `download(for:session:configuration:)` → ``NebulaDownloadHandle``; `resume(from:session:configuration:)`; `pinned(by:sessionConfiguration:configuration:logger:)` → ``NebulaDownload/PinnedDownloadSession`` (reuses N17a `NebulaURLSessionDelegate` as session delegate — zero N17a change).
- ``NebulaDownloadHandle`` — `progress: AsyncThrowingStream<Double, any Error>` + `value() async throws -> URL` + `cancelByProducingResumeData() async throws -> Data?`.
- ``NebulaDownloadDelegate`` — `final class : NSObject, URLSessionDownloadDelegate, Sendable` (derived, no `@unchecked`); per-task download callbacks; `didFinishDownloadingTo` moves the temp file; `didWriteData` → progress; task captured for cancel-with-resume.
- ``NebulaDownloadConfiguration`` — per-call `Sendable` (NOT `Equatable`); fluent `.withDestination`/`.withResume`/`.withMaxResumeAttempts`/`.withResumeDelay`/`.withSleeper`/`.withLogger`.
- ``NebulaPagedSequence`` — generic `<Page: Sendable>` pagination helper; `stream() -> AsyncThrowingStream<Page, any Error>`; custom loop (not `withPolicy`).
- ``NebulaMultipartError`` / ``NebulaDownloadError`` — open-struct errors (`NebulaFailure`, `coarseKind`/`toNebulaError(kind:)`, no new ``NebulaError/Kind`` case).
- Docs: `ArchitectureBodiesDownloads.md`; index link in `Architecture.md` (after `ArchitectureStreaming`); `NebulaPagedSequence` cross-reference in `ArchitectureAsync.md`.

### Notes
- **Delegate routing** — the per-task download delegate receives the download callbacks; SSL/TLS pinning rides the session delegate (session-level auth challenge). `NebulaDownloadDelegate` holds NO pinning; `pinned(by:)` sets the N17a `NebulaURLSessionDelegate` as the session delegate — zero N17a change, zero pinning-logic duplication, no `import Security` in the product target.
- **Custom loops, not `NebulaRetry.withPolicy`** — the paged cursor mutates per page; the download resume `Data` mutates the attempt. `withPolicy`'s `operation` is nullary — it cannot carry mutating state (the SSE `Last-Event-ID` precedent).
- **Gateway-compatibility** — multipart produces a `Data`+content-type that the existing `NebulaHTTPBody.data(_:contentType:)` carries — no new `NebulaHTTPBody` case, no `NebulaHTTPRequest`/parser ripple, the buffered `NebulaHTTPGateway` unchanged.
- **Consumer cancellation** surfaces via the loop (it resumes the completion box with `CancellationError`), NOT via `withCheckedThrowingContinuation` auto-cancellation (which does not throw on Task cancel without a `withTaskCancellationHandler` bridge).
- **Testability limitation** — `URLProtocol` does not cleanly bridge the async `download(for:delegate:)` temp-file path (hangs); the live round-trip is compile-only, pure seams cover the surface (the N17a pragmatic stance).
- **Adversarial code review (end of N17c).** No CONFIRMED bugs.
- No breaking change. No new `NebulaError.Kind` case. No `@available` gate (all N17c APIs below-floor). No new `import CryptoKit`/`import Security`/`import Network`. No `NebulaHTTPGateway` / `NebulaHTTPClient` / `NebulaHTTPBody` / `NebulaHTTPRequest` / `NebulaURLSessionDelegate` / `NebulaHTTPSession` / `Package.swift` change (`dependencies: []` pristine, no `resources:`).

## [0.15.0] - 2026-07-20

> Nebula 0.15.0 — aligned to OS 26 (Liquid Glass). **Streaming (SSE + WebSocket):** the network-hardening Wave N17b (the second sub-wave of the N17 split; N17c bodies+downloads follows). Two **additive** streaming surfaces on top of the existing buffered HTTP gateway — the gateway is **unchanged** (`NebulaHTTPGateway.send` returns a buffered `NebulaHTTPResponse` with `body: Data`; there is no streaming method on `NebulaHTTPClient`), and the N17a pinning is **reused via composition/forwarding** (zero N17a source change, zero pinning-logic duplication).
>
> **SSE — `NebulaSSEEventStream.events(for:session:configuration:) -> AsyncThrowingStream<NebulaSSEEvent, any Error>`.** The CLAUDE.md-mandated concrete return type (a `some AsyncSequence` return is illegal in a protocol requirement; this stream is returned from a `static func`). Internally it iterates the **raw `URLSession.AsyncBytes` byte stream and forms lines manually — NOT `.lines`**: `AsyncLineSequence` skips empty lines, but SSE dispatches on the **blank line**, so `.lines` would drop every dispatch boundary (verified empirically). A pure WHATWG-spec parser (`NebulaSSEParser`, the `internal` testable seam) feeds dispatched `NebulaSSEEvent`s; a documented deviation — a pure-control blank line with no `data:` does NOT yield a spurious empty event (heartbeats are `:` comments, not blank lines). Spec-compliant auto-reconnect with `Last-Event-ID`. The reconnect loop is **custom, NOT `NebulaRetry.withPolicy`** — the request mutates per attempt (the `Last-Event-ID` header advances with the cursor), and `withPolicy`'s `operation` is a nullary closure that cannot mutate the request between attempts. The loop mirrors `withPolicy`'s cancellation contract — cancellation is honored immediately and never retried. `NebulaSSEConfiguration` is `Sendable` but **NOT `Equatable`** (the `@Sendable` sleeper — the `NebulaLogConfiguration` not-`Equatable` flavor); per-call, not process-wide → no `Mutex` accessor.
>
> **WebSocket — a `NebulaWebSocketClient` port + a `NebulaURLSessionWebSocket` `final class : Sendable` façade over `URLSessionWebSocketTask`.** The port is its own axis (WebSocket is not request/response → no `NebulaGateway` inheritance). `NebulaWebSocketMessage` mirrors `URLSessionWebSocketTask.Message` as a Nebula-owned type (never expose Apple's nested enum in a Nebula port); `init?(_:)` is failable with `@unknown default` (the enum is non-frozen). `NebulaWebSocketSessionDelegate` is ONE object per session that does pinning (composition with the N17a `NebulaURLSessionDelegate`) AND the WebSocket lifecycle — its auth-challenge method **forwards** to `pinningDelegate.urlSession(…)` (public + callable; zero pinning-logic duplication). `NebulaWebSocketSession.pinned(by:)/open(url:using:)` is the ergonomic entry. `sendPing` wraps the completion-handler form in `withCheckedThrowingContinuation` (no async `sendPing` overlay exists).
>
> **Three load-bearing corrections from the N17b research/plan.** (1) **`URLSessionWebSocketTask` IS `NS_SWIFT_SENDABLE`** (`NSURLSession.h:1121`) — the prior research note's "non-Sendable" premise was FALSE on this SDK → the façade's `let task: URLSessionWebSocketTask` and the `final class : NSObject, URLSessionWebSocketDelegate, Sendable` delegate both **derive** `Sendable` with NO `@unchecked` (the `NebulaUNNotificationCenter` analogy — `URLSessionWebSocketDelegate` is an `@objc` protocol NOT `NS_SWIFT_SENDABLE`, but that does not block derived `Sendable` on a `final class` with all-`let` Sendable props; probed against the Xcode 27 Beta 3 SDK with `swiftc -typecheck -swift-version 6 -strict-concurrency=complete -warnings-as-errors` → EXIT=0, zero warnings). (2) **Iterate the raw `AsyncBytes` byte stream, NOT `.lines`** — `AsyncLineSequence` skips empty lines but SSE dispatches on the blank line (verified empirically). (3) **`AsyncThrowingStream` cancellation semantics** — `Iterator.next()` returns `nil` on consumer cancellation (the consumer's `for try await` ends **normally**, it does NOT throw `CancellationError`); `onTermination` cancels the internal loop so the `bytes(for:)` task tears down. The plan/vault's "CancellationError rethrown to the consumer" was wrong; corrected to "the stream terminates gracefully on consumer cancellation" (the internal `finish(throwing: CancellationError())` is a no-op for a consumer that has already stopped — it exists to tear down the internal `bytes(for:)` task via `onTermination → loop.cancel()`).
>
> **Sendability — all N17b types below the `.v26` floor → no `@available` gate anywhere.** `URLSession.bytes(for:)` (macOS 12/iOS 15/watchOS 8/tvOS 15/visionOS 1.0+), `URLSessionWebSocketTask`/`URLSessionWebSocketDelegate` (macOS 10.15/iOS 13/watchOS 6/tvOS 13/visionOS 1.0+), `AsyncThrowingStream` (macOS 10.15/iOS 13/watchOS 6/tvOS 13). `URLSessionWebSocketTask` is `NS_SWIFT_SENDABLE`; `NebulaWebSocketSessionDelegate` + `NebulaURLSessionWebSocket` derive `Sendable`; all public value types derive `Sendable` from value-type fields. **Zero `@unchecked` on any value type** (the only `@unchecked` in N17b is the test echo server — a `final class @unchecked Sendable` audited reference type, the binding forbids `@unchecked` on value types only). `import Foundation` everywhere; `import Security` only in the N17a delegate (reused, not redeclared); `import Network` only in the test echo server; **no new `import CryptoKit`**.
>
> **Testability asymmetry.** SSE is exercised via a `URLProtocol`-backed `URLSession` (`URLProtocol` intercepts `URLSession.bytes(for:)` data tasks; a `hang` flag serves the header without the body so cancellation is testable without a hang). WebSocket is exercised via an `NWListener` echo server (`URLProtocol` does NOT intercept `URLSessionWebSocketTask`, so the live round-trip needs a real listener — `Network.framework` is admissible, the `NebulaHTTPServer` precedent); the echo server handles the client handshake via `NWProtocolWebSocket.Options.setClientRequestHandler` + `autoReplyPing` and echoes each message with the same opcode — the echo `send` carries `NWProtocolWebSocket.Metadata(opcode:)` in the `ContentContext` or the frame is invalid and the client receives "Socket is not connected" (a real bug found and fixed during the test). The pure logic (the `NebulaSSEParser`, the message bridge, the error mapping, the delegate lifecycle + auth-challenge forwarding, the session builder) is unit-tested without a live socket. `NebulaSSEError`/`NebulaWebSocketError` are open-struct errors mirroring `NebulaHTTPServerError` (no new `NebulaError.Kind` case); `NebulaWebSocketError.closed(code:reason:)` carries the close code in metadata. Ships as Nebula 0.15.0 (additive minor within Nebula 26 — new public types; no breaking change). Tagging deferred to the owner's gate decision.

### Added — Wave N17b (Streaming — SSE + WebSocket)
- ``NebulaSSEEventStream`` — `events(for:session:configuration:) -> AsyncThrowingStream<NebulaSSEEvent, any Error>`; raw-byte line splitting (NOT `.lines`); custom reconnect loop with `Last-Event-ID`.
- ``NebulaSSEEvent`` — `Sendable`/`Equatable`/`Hashable` (id/event/data/retry).
- ``NebulaSSEParser`` — `internal` pure WHATWG state machine (the testable seam).
- ``NebulaSSEConfiguration`` — `Sendable` (NOT `Equatable`) per-call config; fluent `.withReconnect`/`.withMaxReconnectAttempts`/`.withReconnectDelay`/`.withSleeper`.
- ``NebulaWebSocketClient`` — the port (own axis, no `NebulaGateway` inheritance).
- ``NebulaWebSocketMessage`` — Nebula-owned mirror of `URLSessionWebSocketTask.Message`; failable `init?(_:)` (`@unknown default`); `rawMessage`.
- ``NebulaURLSessionWebSocket`` — `final class : NebulaWebSocketClient, Sendable` façade; `internal mapSend`/`mapReceive`/`mapPing`/`isCancellation` testable seams.
- ``NebulaWebSocketSessionDelegate`` — `final class : NSObject, URLSessionWebSocketDelegate, Sendable` (derived, no `@unchecked`) — combined pinning (composition/forwarding of the N17a `NebulaURLSessionDelegate`) + WebSocket lifecycle.
- ``NebulaWebSocketSession`` / ``NebulaPinnedWebSocketSession`` — `pinned(by:configuration:logger:onOpen:onClose:)` builder + `open(url:protocols:using:logger:)` / `open(request:using:logger:)` ergonomic entry.
- ``NebulaSSEError`` / ``NebulaWebSocketError`` — open-struct errors (`NebulaFailure`, `coarseKind`/`toNebulaError(kind:)`, no new ``NebulaError/Kind`` case); `closed(code:reason:)` carries the close code in metadata.
- Docs: `ArchitectureStreaming.md`; index link in `Architecture.md` (after `ArchitectureSSLPinning`).

### Notes
- **Three load-bearing corrections from the research/plan.** `URLSessionWebSocketTask` IS `NS_SWIFT_SENDABLE` (the prior note was wrong); the raw `AsyncBytes` byte stream is iterated (NOT `.lines` — `AsyncLineSequence` skips empty lines but SSE dispatches on the blank line); `AsyncThrowingStream` cancellation ends the consumer's loop normally (does NOT throw `CancellationError` — the plan's "rethrown" claim was wrong, corrected to "terminates gracefully").
- **Reused N17a pinning via composition/forwarding** — the WebSocket delegate forwards the auth-challenge method to the held `NebulaURLSessionDelegate` (zero N17a change, zero pinning-logic duplication); pinning rides the session delegate (inherited `URLSessionDelegate`).
- **Adversarial code review (end of N17b).** No CONFIRMED bugs. The review found and fixed one real bug during testing (the echo server's `send` needed `NWProtocolWebSocket.Metadata(opcode:)` or the frame was invalid).
- No breaking change. No new `NebulaError.Kind` case. No `@available` gate (all streaming APIs below-floor). No new `import CryptoKit`. No `NebulaHTTPGateway` / `NebulaURLSessionDelegate` / `NebulaHTTPSession` / `NebulaGatewayConfiguration` / `Package.swift` change (`dependencies: []` pristine, no `resources:`).

## [0.14.0] - 2026-07-20

> Nebula 0.14.0 — aligned to OS 26 (Liquid Glass). **SSL/TLS public-key pinning:** the network-hardening Wave N17a (the first sub-wave of the N17 split; N17b streaming / N17c bodies+downloads follow). Pinning is a **transport-layer** concern, not an interceptor concern — a pin failure surfaces as a `URLError` from `URLSession` *before/under* the `data(for:)` call, so trust evaluation has to happen at the `URLSessionDelegate` layer (an `adapt`/`retry` interceptor only mutates the `URLRequest` / reacts to a thrown error, it cannot evaluate trust). The interceptor surface already shipped in N10/0.7.0 (``NebulaHTTPInterceptor``/``NebulaHTTPInterceptorChain``/``NebulaAuthInterceptor``); N17a adds pinning as a separate transport concern and **does not touch ``NebulaHTTPGateway`` at all** — the gateway already accepts an opaque `session: URLSession`, so a caller injects a delegate-configured session today with zero gateway changes (Option A). No `NebulaGatewayConfiguration.pinning` field (pinning is per-session, not per-config); no process-wide `NebulaSSLPinningConfig` accessor (pinning is not process-wide like logging/measurement); the ``Nebula`` config-contracts list is unchanged.
>
> **`import Security` is in-bounds** — the Keychain precedent (`import Security` in `Architecture/Keychain/`). The research's open question ("`import Security` not on the CLAUDE.md allowed list") is resolved: Security is a non-UI Apple system framework, admissible per the binding. **The Security framework has NO `.swiftinterface`** — it is C/Obj-C via `module.modulemap`; the `.h` headers are the ground truth (WebFetch hallucinates availability). All pinning-relevant symbols are below the `.v26` floor on every platform → **no `@available` gate anywhere in N17a**: `SecTrustEvaluateWithError` (mac 10.14/iOS 12/tvOS 12/watchOS 5), `SecTrustCopyCertificateChain` (mac 12/iOS 15/tvOS 15/watchOS 8 — preferred over the deprecated `SecTrustGetCertificateAtIndex`), `SecCertificateCopyKey` (mac 10.14/iOS 12/tvOS 12/watchOS 5 — cross-platform, NOT the deprecated platform-split `SecCertificateCopyPublicKey`), `SecKeyCopyExternalRepresentation` (mac 10.12/iOS 10/tvOS 10/watchOS 3). `URLSessionDelegate` is `NS_SWIFT_SENDABLE`; `urlSession(_:didReceive:completionHandler:)` is `@objc optional` with a `@escaping @Sendable` completion and no async variant.
>
> **Sendability — `final class : NSObject, URLSessionDelegate, Sendable` DERIVED, no `@unchecked`.** Probed against the Xcode 27 Beta 3 SDK with `swiftc -typecheck -swift-version 6 -strict-concurrency=complete -warnings-as-errors` → EXIT=0, zero warnings. `URLSessionDelegate` is `NS_SWIFT_SENDABLE`, so conformance to a Sendable `@objc` protocol does not block derived `Sendable` on a `final class` whose only stored props are immutable `let`s of Sendable type. This matches the ``NebulaUNNotificationCenter`` precedent (N15a). `NSObject` is Foundation (not UIKit); required because `URLSessionDelegate` is an `@objc` protocol with `@objc optional` methods. **The key contrast with N15b**: there the non-`Sendable` `BGTask` arrived in a `@Sendable` closure and could not be stored in a `Mutex` (region-isolation wall) → required a `@unchecked Sendable` reference-type box. Here no non-Sendable type is stored — the policy is a Sendable value, the `SecTrust` is consumed and discarded inside the synchronous delegate call (never persisted). **Zero `@unchecked`** in all of N17a (policy/value/result/error types derived; the delegate derived; ``NebulaPinnedSession`` derived).
>
> **Testability — synthetic `SecTrust` + `disposition(for:policy:trust:)` seam.** The pure evaluator (``NebulaSSLPinningEvaluator/evaluate(trust:host:policy:)``) is fully unit-testable on the macOS host with a **synthetic `SecTrust`**: a self-signed RSA-2048 cert (CN=test.example.com) is embedded as a `[UInt8]` literal (694 bytes, generated offline, baked into the test source — NO SPM `resources:`, no bundle); the golden pin (`7badc2c8…3b2a`, SHA-256 of the public-key DER) is computed once via the same API path and hardcoded. The delegate method itself is **NOT round-trip-testable** — `URLProtectionSpace.serverTrust` is `nil` unless the system created the space during a real handshake, and the public `URLProtectionSpace.init` has no `serverTrust` parameter. Resolution: the disposition mapping is extracted as an `internal` helper (``NebulaURLSessionDelegate/disposition(for:policy:trust:)``) and unit-tested directly; the delegate body is a thin guard → evaluate → map → completion. The live `URLSession`+delegate+TLS round-trip is a documented compile-only limitation (mirrors the ``NebulaUNNotificationCenter`` headless limitation).
>
> **SPKI algorithm — OWASP "any position", additive to system trust.** Match **any** cert in the chain (leaf or intermediate/CA) — survives leaf rotation. ``NebulaSSLPinning/validateChainFirst`` defaults to `true` (run `SecTrustEvaluateWithError` first; pinning never replaces the OS trust store). The SHA-256 of the public-key DER goes through the existing `Data.nebulaDigest(of: .sha256)` → ``NebulaHashAlgorithm``/sha256 → `CryptoKit.SHA256` — **no new `import CryptoKit`** (the only file that imports CryptoKit remains `NebulaHashAlgorithm.swift`; the "one file imports CryptoKit" invariant is preserved). Host lookup is factored as `internal resolvedPins(for:policy:)` — exact match, then a parent-domain walk when `includeSubdomains`, stopping before the single-label public suffix; matching is **case-insensitive** (RFC 1035). ``NebulaHTTPSession/pinned(by:configuration:logger:)`` returns a ``NebulaPinnedSession`` carrying BOTH the `URLSession` and the delegate — `URLSession` does NOT strongly retain its delegate, so the caller must retain the ``NebulaPinnedSession`` value (the footgun is documented). ``NebulaSSLPinningError`` is an open-struct error mirroring ``NebulaHTTPServerError`` (no new ``NebulaError/Kind`` case); the delegate does NOT throw (the `@objc optional` method has no `throws`) — on failure it logs and calls `.cancelAuthenticationChallenge`, and `URLSession` surfaces a `URLError` to ``NebulaHTTPGateway``, which already bridges `URLError → NebulaError(urlError:)` (no gateway change, no new bridge wired). Ships as Nebula 0.14.0 (additive minor within Nebula 26). Tagging deferred to the owner's gate decision.

### Added — Wave N17a (SSL/TLS public-key pinning)
- ``NebulaSSLPinningPin`` — 32-byte SHA-256 SPKI digest; `init?(digest:)` / `init?(hexDigest:)` (via `Data(nebulaHexEncoded:)`, re-validates 32 bytes) / `hexDigest`.
- ``NebulaSSLPinning`` — `Sendable` policy value type: `hostPins` / `includeSubdomains` / `validateChainFirst` (default `true`) / `failClosedForUnknownHosts` (default `true`); fluent `.withHostPins`/`.withIncludeSubdomains`/`.withValidateChainFirst`/`.withFailClosedForUnknownHosts`; `static pins(for:_:)` convenience. Plus the nested ``NebulaSSLPinning/HostPins`` (host + pin set).
- ``NebulaSSLPinningResult`` — `matched(pin:certificateIndex:)` / `noMatchingPin` / `noPinForHost` / `chainValidationFailed(message:)` / `spkiExtractionFailed(message:)`.
- ``NebulaSSLPinningEvaluator`` — pure `static evaluate(trust:host:policy:)`; `internal resolvedPins(for:policy:)` (case-insensitive host lookup + subdomain walk).
- ``NebulaURLSessionDelegate`` — `final class : NSObject, URLSessionDelegate, Sendable` façade (derived `Sendable`, no `@unchecked`); `internal disposition(for:policy:trust:)` testable seam.
- ``NebulaHTTPSession`` / ``NebulaPinnedSession`` — `pinned(by:configuration:logger:)` session builder returning both the `URLSession` and the delegate.
- ``NebulaSSLPinningError`` — open-struct error (`NebulaFailure, Equatable, Hashable`), nested `Kind`, `coarseKind` / `toNebulaError(kind:)` (no new ``NebulaError/Kind`` case); mirrors ``NebulaHTTPServerError``.
- Docs: `ArchitectureSSLPinning.md`; index link in `Architecture.md` (after `ArchitectureAuth`).

### Notes
- **Scope correction.** The N17a research listed the wave as "interceptors + pinning scaffolding"; the interceptor half already shipped in N10/0.7.0, and pinning is transport-layer (a pin failure surfaces as `URLError` from `URLSession` before/under `data(for:)` → trust eval belongs at `URLSessionDelegate`, not an `adapt`/`retry` interceptor) → the gateway is untouched (Option A).
- **Adversarial code review (end of N17a).** No CONFIRMED bugs. Two low-severity plausible findings, both incorporated: (1) `.spkiExtractionFailed` now also fires when **every** cert in the chain fails key/DER extraction (previously the all-fail path fell through to `.noMatchingPin`, which was a misleading diagnostic for a caller bridging to ``NebulaSSLPinningError``); a single un-extractable key is still skipped (not fatal). (2) host matching is now **case-insensitive** (RFC 1035 — `host` and the stored `HostPins.host` are both `.lowercased()` before comparison; stored data is not mutated) — previously a mixed-case `HostPins(host:)` would fail to match a lowercase `URLProtectionSpace.host`.
- No breaking change. No new `NebulaError.Kind` case. No `@available` gate (all `Sec*` + `URLSessionDelegate` below-floor). No new `import CryptoKit`. No `NebulaHTTPGateway` / `NebulaHTTPInterceptor` / `NebulaGatewayConfiguration` / `Package.swift` change (`dependencies: []` pristine, no `resources:`).

## [0.13.0] - 2026-07-20

> Nebula 0.13.0 — aligned to OS 26 (Liquid Glass). **Background tasks:** `BGTaskScheduler` is `API_UNAVAILABLE(macos) API_UNAVAILABLE(watchos)` — background tasks are an iOS / tvOS / visionOS surface. ``NebulaBackgroundTaskScheduler`` (a `Sendable` port) carries the five scheduling requirements (``NebulaBackgroundTaskScheduler/register(_:)`` / ``NebulaBackgroundTaskScheduler/submit(_:)`` / ``NebulaBackgroundTaskScheduler/cancel(_:)`` / ``NebulaBackgroundTaskScheduler/cancelAll()`` / ``NebulaBackgroundTaskScheduler/pendingRequests()``); the launch-handler surface is **not** on the port — it lives on the config. ``NebulaBGTaskScheduler`` (a `final class : NebulaBackgroundTaskScheduler, Sendable`, **no `NSObject`** — there is no `@objc` protocol to back, unlike ``NebulaUNNotificationCenter``) is the façade over `BGTaskScheduler.shared`. `BGTaskScheduler.shared` is non-`Sendable` AND a shared singleton → fetched **locally per method, never stored** (the ``NebulaDefaults`` precedent does not apply; the singleton cannot be `sending`-consumed). `register(forTaskWithIdentifier:using:launchHandler:)` takes `using: nil` explicit (the param has no default); the launch handler bridges the delivered `BGTask` to a Sendable ``NebulaBackgroundTask`` handle and forwards it to the config's `launch`. `Sendable` is **derived** for the façade — no `@unchecked` on it.
>
> **New gating precedent — `@available(<platform>, unavailable)` declaration gate for an SDK symbol `API_UNAVAILABLE` on a Nebula type.** `BackgroundTasks.framework` is physically present on all 5 SDKs (headers + `.tbd` on macOS/watchOS too), so `#if canImport(BackgroundTasks)` is `true` on macOS/watchOS — it gates nothing, and the subsequent `BGTaskScheduler.shared` reference then fails. The compile-safe gate is a **type-level `@available(macOS, unavailable) @available(watchOS, unavailable)` declaration** on the Nebula façade (the ``NebulaLogStoreExporter`` precedent): declaring a Nebula symbol unavailable suppresses body type-checking on macOS/watchOS, so the unavailable `BGTaskScheduler.shared` reference inside isn't validated there. `@available(macOS 26, unavailable)` is a syntax error — `unavailable` takes no version. This is form (c) of the **4-form gating taxonomy** now consolidated: (1) `@available(<platform>, unavailable)` declaration gate on a Nebula symbol [N15b]; (2) `#if !os(<platform>)` compile gate for an SDK symbol `API_UNAVAILABLE` that can't take a declaration gate [N15a]; (3) `#if canImport(<framework>)` whole-file gate for a genuinely absent framework [reserved for the future]; (4) `#if swift(>=6.4)` + `if #available(<platform> N, *)` for above-floor OS-27 SDK symbols [N15b `submit`].
>
> **Sendability — `@unchecked Sendable` reference-type box for the non-`Sendable` `BGTask`.** `BGTask` is non-`Sendable` and system-delivered **inside** the `@Sendable` launch callback. Storing it directly in a `Mutex<[String: BGTask]>` fails whole-module Swift 6 with a **region-isolation wall** (`'inout sending' parameter '$0' cannot be task-isolated`) — a non-`Sendable` class arriving as a closure param cannot be `sending`-transferred into a `Mutex` region the compiler can't prove exclusive (the ``NebulaDefaults`` `Mutex<non-Sendable>` precedent does not apply — `UserDefaults.standard` arrives at a public `sending` API boundary the caller asserts; `BGTask` arrives in a launch closure). The resolution is a minimal `final class @unchecked Sendable` ``NebulaBGTaskBox`` holding the `BGTask` as an **immutable `let`** (no Mutex, no `sending` init — the plain stored-property init compiles). This is the documented ``NebulaMemoryLogHandler`` precedent — the only `@unchecked` type in the layer, "justified … because it is a reference type, not a Nebula-defined value type." The binding forbids `@unchecked` on **value** types; a once-assigned, immutable, system-owned reference behind an audited `@unchecked` boundary is the permitted exception. The box crosses isolation, the façade holds `Mutex<[String: NebulaBGTaskBox]>` (Sendable boxes → Sendable dictionary → Sendable `Mutex`), and the façade's `Sendable` conformance is **derived** — `@unchecked` is isolated to the single reference-type box. The Sendable ``NebulaBackgroundTask`` handle holds only the identifier + kind + two `@Sendable` closures (``NebulaBackgroundTask/complete(success:)`` / ``NebulaBackgroundTask/onExpiration(_:)``) that capture the **Sendable façade + identifier** (never the `BGTask`) and reach the box through the façade's `Mutex`.
>
> **`submit` dual-path, warning-clean under `.v26`.** The iOS-27 async `BGTaskScheduler.shared.submitTaskRequest(_:)` (an OS-27 symbol) is gated `#if swift(>=6.4)` (absent from the Xcode 26.4 / Swift 6.3 SDK) + a runtime `if #available(iOS 27, tvOS 27, visionOS 27, *)`. The iOS-26 fallback is the deprecated sync `BGTaskScheduler.shared.submit(_:)` (`submitTaskRequest:error:`, deprecated iOS 27) — deprecation warnings fire only when the deployment target ≥ the obsoleted version (`27 > 26`), so under `.v26` the fallback is warning-clean and keeps the façade's headline capability usable on Nebula's own floor. ``NebulaBackgroundTaskConfiguration`` is the seventh config (`Sendable`, NOT `Equatable`); process-wide access via ``NebulaBackgroundTaskConfig``. ``NebulaBackgroundTaskError`` is an open-struct error (``NebulaFailure``, the `NebulaKeychainError` precedent) with a coarse `coarseKind` (scheduling failures → `.cocoa`, the rest → `.unknown`) and a `toNebulaError(kind:)` bridge — **no new ``NebulaError/Kind`` case**; factory statics carry `underlying: NebulaError.Box?` to preserve the SDK `NSError` in every mapping path.
>
> **Testing note (larger constraint than N15a):** every `BackgroundTasks` SDK type is `API_UNAVAILABLE(macos)`. `swift test` runs on the macOS host, where none compile. The all-5 value types / handle / config / port / error run on macOS; the façade and the SDK-mapping round-trip are gated `#if !os(macOS) && !os(watchOS)` — they compile on iOS/tvOS/visionOS (`xcodebuild`-verified) but are dead code on the macOS test host. `BGTaskScheduler.shared` is non-functional in a headless test bundle (no app context) → the façade is never instantiated in tests; the port seam (`FakeBackgroundTaskScheduler`) + the type-level conformance check + the mapping round-trip prove the architecture. The register/submit/cancel integration is a documented limitation. Ships as Nebula 0.13.0 (additive minor within Nebula 26). Tagging deferred to the owner's gate decision.

### Added — Wave N15b (Background tasks)
- ``NebulaBackgroundTaskKind`` — `Sendable` task-kind enum (`.appRefresh` / `.processing`), all-5.
- ``NebulaBackgroundTaskRequest`` — `Sendable` scheduling-request value type, all-5.
- ``NebulaBackgroundTask`` — Sendable launch-time handle (identifier + kind + `@Sendable` `complete`/`onExpiration` closures reaching the `BGTask` through the façade, not by holding it).
- ``NebulaBackgroundTaskScheduler`` — `Sendable` scheduling port.
- ``NebulaBGTaskScheduler`` — `final class : Sendable` façade over `BGTaskScheduler.shared` (no `NSObject`), macOS/watchOS-unavailable.
- ``NebulaBGTaskBox`` — `final class @unchecked Sendable` reference-type wrapper holding the non-`Sendable` `BGTask` (the ``NebulaMemoryLogHandler`` precedent).
- ``NebulaBackgroundTaskConfiguration`` (7th config) + ``NebulaBackgroundTaskConfig`` process-wide accessor.
- ``NebulaBackgroundTaskError`` — open-struct background-task-layer error.
- Docs: `ArchitectureBackgroundTasks.md`; index link in `Architecture.md`; `Nebula.md` configuration-contracts list (Six → Seven); the stale `#if canImport(BackgroundTasks)` reference in `ArchitectureNotifications.md` corrected.

### Notes
- **Gating-precedent correction.** The N15b plan / research recommendation of a `#if canImport(BackgroundTasks)` whole-file gate was empirically wrong — the framework is physically present on macOS/watchOS, so `canImport` is `true` there and gates nothing. The correct gate is the type-level `@available(macOS, unavailable) @available(watchOS, unavailable)` declaration. The 4-form gating taxonomy is consolidated (declaration gate / compile gate / absent-framework gate / above-floor gate).
- **Sendability correction.** The plan's `Mutex<[String: BGTask]>`-no-`@unchecked` design hit a Swift 6 region-isolation wall (a non-`Sendable` `BGTask` arriving as a launch-closure param cannot be `sending`-transferred into the Mutex region). Resolved by a `@unchecked Sendable` reference-type box — the `NebulaMemoryLogHandler` precedent (the binding forbids `@unchecked` on value types, not reference types). `@unchecked` is isolated to the single box; the façade and the handle both derive `Sendable`.
- No breaking change. No new `NebulaError.Kind` case. No `NSObject` base (no `@objc` protocol). No `BGContinuedProcessingTask` (deferred → N15c).

## [0.12.0] - 2026-07-20

> Nebula 0.12.0 — aligned to OS 26 (Liquid Glass). **Notifications + Permission
> status:** `UserNotifications` is available on all 5 platforms at the `.v26`
> floor, so the notifications surface ships all-5 with no framework-level gate.
> ``NebulaNotificationCenter`` (a `Sendable` port) carries the five
> scheduling/authorization requirements
> (``NebulaNotificationCenter/requestAuthorization(options:)`` /
> ``NebulaNotificationCenter/add(_:)`` / ``NebulaNotificationCenter/cancel(_:)`` /
> ``NebulaNotificationCenter/cancelAll()`` /
> ``NebulaNotificationCenter/pendingRequests()``); the delegate-handler surface is
> **not** on the port — it lives on the config.
> ``NebulaUNNotificationCenter`` (a `final class : NSObject,
> NebulaNotificationCenter, UNUserNotificationCenterDelegate, Sendable`) is the
> delegate-adapter façade — `UNUserNotificationCenterDelegate` is an `@objc`
> protocol backed by a `weak` Obj-C reference, so the façade subclasses `NSObject`
> (the ``NebulaHTTPServer`` `Sendable final class` precedent gains an `NSObject`
> base); the delegate methods are sync Obj-C callbacks → a `final class` + a
> `Mutex<``NebulaNotificationsConfiguration``>` (not an actor). `Sendable` is
> **derived** (the only stored property is the `Mutex<Config>`) — no `@unchecked`.
> `UNUserNotificationCenter.current()` is non-Sendable AND a shared singleton, so
> it is fetched **locally per method, never stored** (the singleton cannot be
> `sending`-consumed — the `NebulaDefaults` precedent does not apply); `delegate`
> is `weak` → auto-nils on dealloc → no `deinit`. The config handlers are
> **synchronous-returning** (``NebulaNotificationsConfiguration/willPresent``
> returns ``NebulaNotificationPresentationOptions``,
> ``NebulaNotificationsConfiguration/didReceive`` returns `Void`) to avoid
> capturing the non-`@Sendable` Obj-C completion inside a `@Sendable` closure.
> ``NebulaNotificationsConfiguration`` is the sixth config struct (carries
> `@Sendable` handlers like the family — `Sendable`, NOT `Equatable`); process-wide
> access via ``NebulaNotificationsConfig``. ``NebulaNotificationsError`` is an
> open-struct error (``NebulaFailure``, the `NebulaKeychainError` precedent) with a
> coarse `coarseKind` (scheduling failures → `.cocoa`, the rest → `.unknown`) and
> a `toNebulaError(kind:)` bridge — **no new ``NebulaError/Kind`` case**.
> ``NebulaPermissionStatus`` (an 8-case `Sendable`/`CaseIterable` union-superset
> enum — `notDetermined`/`restricted`/`denied`/`authorized`/`provisional`/
> `ephemeral`/`authorizedAlways`/`authorizedWhenInUse`) bridges
> `UNAuthorizationStatus` (`.ephemeral` is `#if os(iOS)` — App Clips); the unified
> `NebulaPermissions` request port is deferred (app-level glue).
>
> **New gating precedent — `#if !os(<platform>)` for SDK symbols
> `API_UNAVAILABLE`.** The `didReceive` delegate callback, `UNNotificationResponse`,
> and every user-facing `UNNotificationContent` property are `API_UNAVAILABLE(tvos)`.
> Empirically verified via `swiftc -typecheck` across all 5 SDKs that
> `@available(tvOS, unavailable)` on the override fails ("cannot override
> 'userNotificationCenter' which has been marked unavailable") and `if #available(...,
> *)` fails ("'title' is unavailable in tvOS" — the `*` wildcard does NOT exclude
> tvOS for an `unavailable` symbol). The ONLY compile-safe mechanism is
> `#if !os(tvOS)` — applied to the `didReceive` override (absent on tvOS) and the
> content-property mapping (content-less on tvOS). This is distinct from the
> `@available(<platform>, unavailable)` declaration gate (declares a NEBULA symbol
> unavailable) and the `#if canImport(<framework>)` whole-file gate (deferred to
> N15b's `BackgroundTasks`).
>
> **Testing note:** `UNUserNotificationCenter.current()` traps in a headless test
> bundle (signal 6, no app context), so the façade is never instantiated in tests;
> the mapping helpers are `internal` for a round-trip suite with constructible SDK
> types, and `facadeIsAPortConformer` is a type-level check. The `didReceive`
> payload mapping and the unsupported-trigger branch are documented limitations
> (system-only-constructible types).

### Added
- ``NebulaNotificationCenter`` — `Sendable` notifications scheduling/authorization port.
- ``NebulaUNNotificationCenter`` — `final class : NSObject` delegate-adapter façade over `UNUserNotificationCenter.current()`.
- ``NebulaNotificationContent`` / ``NebulaNotificationTrigger`` / ``NebulaNotificationRequest`` / ``NebulaNotificationResponse`` / ``NebulaNotificationPresentationOptions`` / ``NebulaAuthorizationOptions`` — `Sendable` value types (all-5).
- ``NebulaNotificationsConfiguration`` (6th config) + ``NebulaNotificationsConfig`` process-wide accessor.
- ``NebulaNotificationsError`` — open-struct notification-layer error.
- ``NebulaPermissionStatus`` — `Sendable` permission-status value enum + `UNAuthorizationStatus` bridge.
- Docs: `ArchitectureNotifications.md` + `ArchitecturePermissions.md`; index links in `Architecture.md`; `Nebula.md` configuration-contracts list (Five → Six).

### Notes
- New gating precedent: `#if !os(<platform>)` for SDK symbols `API_UNAVAILABLE` (distinct from `@available(<platform>, unavailable)` and `#if canImport(<framework>)`).
- Foundation + `UserNotifications` + `Synchronization` only; `Sendable` derived throughout (no `@unchecked` on any N15a type); no `#if canImport`, no `import CoreLocation`.
- Deferred: `.location` trigger, `setBadgeCount`, categories + delivered-notification management, the unified `NebulaPermissions` request port, and `NebulaBackgroundTask` (→ N15b).

## [0.11.0] - 2026-07-20

> Nebula 0.11.0 — aligned to OS 26 (Liquid Glass). **Feature flags:** there is no
> Apple-native remote-config or feature-flag API (zero `FeatureFlag`/
> `RemoteConfig`/`RolloutConfig` hits in `Foundation.swiftmodule`, Xcode 27 Beta 3),
> and `dependencies: []` forbids Firebase/LaunchDarkly — so a remote flag is
> necessarily a **port** the app conforms. Nebula ships the Foundation-tier
> pattern, not a backend. ``NebulaFlagValue`` (a `Sendable`/`Equatable`/`Hashable`
> value enum: `.bool`/`.string`/`.int`/`.double`/`.json(Data)`,
> `CustomStringConvertible` derived; no `Codable` yet — arrives with the persistence
> follow-up) is the storage representation. ``NebulaFeatureFlags`` (a `Sendable`
> port) has ONE requirement ``NebulaFeatureFlags/value(forKey:)`` returning
> ``NebulaFlagValue?``, plus a default extension of typed accessors
> (`bool`/`string`/`int`/`double`/`number`/`json`) every conformer inherits — the
> seam model mirrors ``NebulaPreferences``; `int`/`double` return only their own
> case (no silent coercion), `number` coerces either to `Double`, `json` decodes a
> `.json(_:)` blob via per-call `JSONDecoder()` (decoupled from
> `NebulaJSONDecoder`), and only `json` throws (flag errors surface as
> `DecodingError` — **no new ``NebulaError/Kind`` case**).
> ``NebulaLocalFeatureFlags`` (a `final class` wrapping
> `Mutex<[String: NebulaFlagValue]>`) is the in-memory façade — `Sendable`
> derived, no `@unchecked`; the `final class` absorbs the `~Copyable` `Mutex`; the
> store is a `Sendable` value type, so the init takes it by value (**no `sending`**,
> unlike `NebulaDefaults`'s `UserDefaults`); `setValue(nil)` removes.
> ``NebulaRemoteFeatureFlags`` refines the port with `refresh() async throws` (the
> conformer serves the last-fetched cache; the backend is app-supplied; deviates
> from the research's non-throwing `refresh() async` — honest about fetch failure).
> ``NebulaCompositeFeatureFlags`` (a `Sendable` struct + `[any NebulaFeatureFlags]`
> + `withSource(_:)`, first-non-nil resolution — mirrors
> `NebulaHTTPInterceptorChain`) is a generic resolver; the app wires
> `[localOverrides, remote, builtInDefaults]` — the composite does not hardcode
> local/remote/defaults. It conforms to ``NebulaFeatureFlags``, so the typed
> accessors flow through. **No process-wide accessor** — all `final class` store
> façades are constructed-and-passed at the composition root (the `*Config` `Mutex`
> family is reserved for configuration values). **Deferred:**
> `NebulaDefaults`-backed persistent overrides (research marks optional —
> follow-up; needs `NebulaFlagValue: Codable`); SwiftUI `@Environment` injection /
> an `@Observable` flag manager (Cosmos-only); the remote backend itself
> (app-supplied); rollout-% / audience targeting (backend-computed — Nebula
> evaluates locally on a fetched value). 752 Nebula tests / 151 suites + 12 Aurora
> tests / 3 suites green; zero concurrency warnings. DocC clean (the inherited
> `value(forKey:)` DocC link qualified to ``NebulaFeatureFlags/value(forKey:)``).
> No breaking change.

### Added — Wave N14 (Feature flags)
- **`NebulaFlagValue`** (`Sources/Nebula/Architecture/FeatureFlags/NebulaFlagValue.swift`)
  — a `Sendable`/`Equatable`/`Hashable`/`CustomStringConvertible` value enum:
  `.bool(Bool)`/`.string(String)`/`.int(Int)`/`.double(Double)`/`.json(Data)`
  (derived). `.int`/`.double` stored distinctly; `number(forKey:)` coerces either
  to `Double`.
- **`NebulaFeatureFlags`** (`…/FeatureFlags/NebulaFeatureFlags.swift`) — a
  `Sendable` port with one requirement `value(forKey:) -> NebulaFlagValue?` and a
  default extension: `bool`/`string`/`int`/`double`/`number`/`json(_:forKey:)`
  (`json` throws, per-call `JSONDecoder()`; the rest non-throwing).
- **`NebulaLocalFeatureFlags`** (`…/FeatureFlags/NebulaLocalFeatureFlags.swift`) —
  a `final class` wrapping `Mutex<[String: NebulaFlagValue]>`; `init(_ flags:)`
  (no `sending`), `value(forKey:)`/`setValue(_:forKey:)` (nil removes)/
  `removeValue(forKey:)`/`removeAll()`; derived `Sendable`, no `@unchecked`.
- **`NebulaRemoteFeatureFlags`** (`…/FeatureFlags/NebulaRemoteFeatureFlags.swift`)
  — `: NebulaFeatureFlags` + `refresh() async throws` (app-supplied backend).
- **`NebulaCompositeFeatureFlags`** (`…/FeatureFlags/NebulaCompositeFeatureFlags.swift`)
  — a `Sendable` struct holding `sources: [any NebulaFeatureFlags]`;
  `withSource(_:)` append-builder; first-non-nil `value(forKey:)`; conforms to
  `NebulaFeatureFlags`.
- **`Tests/NebulaTests/ArchitectureFeatureFlagsTests.swift`** — 31 tests / 6 suites:
  `NebulaFlagValue` (equatable, distinct-cases-not-coerced, Hashable, description,
  Sendable-across-Task); `NebulaLocalFeatureFlags` façade (empty, each case round-trip,
  typed accessors, mismatched-case nil, `number` coercion, `setValue(nil)` removes,
  `removeValue`/`removeAll`, port conformance, `json` decode + throw on corrupt);
  `NebulaLocalFeatureFlags` concurrency (Sendable-across-Task, 50-task concurrent
  `setValue`/`value`); `NebulaFeatureFlags` port seam on a custom `MapFlags`
  conformer (typed accessors + `json` bridge + existential holds either conformer);
  `NebulaRemoteFeatureFlags` (refines base port, `refresh()` populates cache,
  usable as a composite source); `NebulaCompositeFeatureFlags` (first-non-nil,
  first-source shadows later, absent → nil, empty composite, `withSource` leaves
  original unchanged, typed accessors flow through, `[local, remote, defaults]`
  local-overrides-win, Sendable-across-Task).

### Docs — Wave N14
- **`ArchitectureFeatureFlags.md`** (`Nebula.docc/`) — an architecture article
  (mirror of `ArchitecturePreferences.md`): no Apple-native remote-config API;
  `NebulaFlagValue` + the one-requirement port + typed default-extension bridges
  + the `Mutex`-backed façade + the remote port + the priority-ordered composite;
  "Why a Mutex and a final class"; "What is deferred".
- **`Architecture.md`** — `- <doc:ArchitectureFeatureFlags>` inserted after
  `- <doc:ArchitectureKeychain>` (NOT added to `Nebula.md` `### Configuration
  contracts` — feature flags are an Architecture-layer port+façade, not a config
  struct).

## [0.10.0] - 2026-07-20

> Nebula 0.10.0 — aligned to OS 26 (Liquid Glass). **Environment value + reader
> pattern:** Apple provides no Foundation `Environment` value type — the idiom is
> the Xcode `Configuration` build setting fed from `.xcconfig` + schemes and
> written into the app's `Info.plist` (a key, conventionally `Configuration`, set
> from `$(CONFIGURATION)`). Nebula ships the **value + reader**, not the wiring.
> ``NebulaEnvironment`` (a closed `String`-backed enum: `.development`/`.staging`/
> `.production`; `Sendable`/`Equatable`/`Hashable`/`CaseIterable`/
> `CustomStringConvertible`; ``NebulaEnvironment/default`` is ``production`` —
> safe-fail-to-production) round-trips that string.
> ``NebulaEnvironment/fromBundle(_:key:)`` reads `object(forInfoDictionaryKey:)`
> (default key `"Configuration"`, default `bundle .main`), casts `Any? → String?`
> **before** crossing isolation (the `infoDictionary` values are `Any` and not
> Sendable), and resolves to ``NebulaEnvironment/default`` on an absent, unknown,
> or non-`String` value — it never returns `nil`. It is a pure function over the
> Sendable `Bundle`; no `Mutex` is needed.
> ``NebulaEnvironmentConfiguration`` (the fifth cross-cutting configuration
> contract) carries the resolved environment plus per-environment `baseURLs` and
> string `overrides`; ``NebulaEnvironmentConfiguration/baseURL(for:)`` returns
> `nil` for an unregistered environment (Nebula ships no built-in URLs).
> ``NebulaEnvironmentConfig`` holds the current config in a `Mutex` (process-wide
> ergonomics) alongside explicit-parameter DI (the two-path rule).
> `NebulaEnvironmentConfiguration` is `Sendable`-not-`Equatable` (family posture;
> no `@unchecked`). **Deferred (app-tier):** `.xcconfig`/scheme/`Info.plist`
> wiring; a `ProcessInfo`-based reader (documented alternative — the
> `Info.plist`-keyed reader is the only one shipped); a reader façade (a value
> builder suffices). Naming `Configuration`/`Config` split mirrors the four-family
> convention (avoids the `NebulaEnvironmentConfigConfig` stutter). 721 Nebula
> tests / 145 suites + 12 Aurora tests / 3 suites green; zero concurrency
> warnings. DocC clean. No breaking change.

### Added — Wave N13 (Environment value + reader)
- **`NebulaEnvironment`** (`Sources/Nebula/Environment/NebulaEnvironment.swift`)
  — a closed `String`-backed enum: `.development`/`.staging`/`.production`;
  `Sendable`/`Equatable`/`Hashable`/`CaseIterable`/`CustomStringConvertible`
  (derived). `static let default = .production`.
- **`NebulaEnvironment.fromBundle(_:key:)`** — reads `object(forInfoDictionaryKey:)`
  (default key `"Configuration"`, default `bundle .main`), casts `Any? → String?`
  before crossing isolation, resolves to `.default` on absent/unknown/non-`String`
  (safe-fail-to-production, never `nil`). Pure function, no `Mutex`.
- **`NebulaEnvironmentConfiguration`** (`Sources/Nebula/Environment/…`) — the fifth
  cross-cutting config struct: `environment: NebulaEnvironment`,
  `baseURLs: [NebulaEnvironment: URL]`, `overrides: [String: String]`; `.with*`
  builders returning the concrete type; `baseURL(for:)` (nil if unregistered),
  `value(for:)`; `static let default`. `Sendable`-not-`Equatable` (family posture).
- **`NebulaEnvironmentConfig`** — caseless enum + `Mutex<NebulaEnvironmentConfiguration>`
  + `get()`/`set(_:)`; the process-wide ergonomic path alongside explicit-parameter DI.
- **`Tests/NebulaTests/EnvironmentTests.swift`** — 23 tests / 4 suites: the enum
  (raw values, `CaseIterable` count, equality/Hashable/description, `default`,
  `init(rawValue:)`); the reader (absent-key → `.production`, unknown → `nil`→
  `.default`, valid raw-value resolution, default key `"Configuration"`); the
  config value (init defaults, `.with*` preserve other fields, `baseURL(for:)`
  resolves + nil-when-unregistered, `value(for:)`, Sendable-across-closure); the
  `NebulaEnvironmentConfig` accessor in a `@Suite(.serialized)` suite.

### Docs — Wave N13
- **`Environment.md`** (`Nebula.docc/`) — a top-level article (sibling to
  `Standardize.md`/`Measure.md`, the `ArchitecturePreferences.md` prose model):
  the Apple idiom has no Foundation value type; `fromBundle` reader with the
  `Any → String` Sendability step; safe-fail-to-production; app-tier wiring
  deferred; `NebulaEnvironmentConfiguration` + the `Mutex` accessor + two-path DI.
- **`Nebula.md`** — `- <doc:Environment>` inserted after `- <doc:Standardize>`;
  `NebulaEnvironmentConfiguration` added to the `### Configuration contracts` list
  (five structs).

## [0.9.0] - 2026-07-20

> Nebula 0.9.0 — aligned to OS 26 (Liquid Glass). **User-error bridge:** a
> Foundation-tier value the presentation layer (Cosmos / the app) renders, produced
> by a configuration-layer map from the closed ``NebulaError`` envelope —
> `NebulaError → NebulaUserError?`. **Mapping only — no new ``NebulaError/Kind``
> cases.** ``NebulaUserError`` (a `Sendable`/`Equatable`/`Hashable` struct:
> `message` + `recoveryActions: [RecoveryAction]` + `helpAnchor`) is the *output* of
> the map — the **opposite direction** from ``NebulaFailure`` (which bridges a
> layer error *into* the envelope), so it is a plain value, **not** a
> ``NebulaFailure``. ``RecoveryAction`` (`.retry`/`.cancel`/`.dismiss`/`.custom(String)`)
> is Nebula-authored because Apple's `RecoverableError` is closure-based, not
> value-based. ``NebulaErrorConfiguration/withUserMessageMap(_:)`` installs a
> `@Sendable` map keyed by ``(NebulaError/Kind, [String: String])`` (the dictionary
> is ``NebulaError/metadata``) returning an optional ``NebulaUserError``; default
> `{ _, _ in nil }` (opt-in). ``NebulaUserError/default(for:context:)`` ships an
> English fallback per `Kind` with HIG-neutral tone (overridable; L10n via
> `String(localized:)` at the app layer — Nebula emits developer-facing English
> only). ``NebulaErrorConfiguration/userError(for:)`` and the
> ``NebulaErrorConfig/userError(for:)`` accessor are **not** gated on
> ``NebulaErrorConfiguration/isEnabled`` (user-message mapping is orthogonal to
> reporting). `NebulaErrorConfiguration` stays `Sendable`-not-`Equatable` (the
> `@Sendable` closures disqualify `Equatable`). **Refuted / deferred:**
> `RecoveryURL` (not public Apple API — only a private PassKit symbol);
> `NebulaError` adopting `RecoverableError` (closure-based — app/Cosmos opt-in);
> a `NebulaErrorPresenter` port (Cosmos-only — presentation is UI). 698 Nebula
> tests / 141 suites + 12 Aurora tests / 3 suites green; zero concurrency
> warnings. DocC clean. No breaking change — `Kind` enum unchanged,
> `NebulaFailure` toolkit unchanged.

### Added — Wave N12 (User-error bridge)
- **`NebulaUserError`** (`Sources/Nebula/Architecture/Errors/NebulaUserError.swift`)
  — a `Sendable`/`Equatable`/`Hashable` user-facing error value: `message`,
  `recoveryActions: [RecoveryAction]`, `helpAnchor: String?`. **Not** a
  `NebulaFailure` (opposite direction — output of the config map, not a layer error
  bridged into the envelope).
- **`RecoveryAction`** (same file) — a `Sendable`/`Equatable`/`Hashable`/
  `CustomStringConvertible` enum: `.retry`/`.cancel`/`.dismiss`/`.custom(String)`.
  Nebula-authored because Apple's `RecoverableError` is closure-based.
- **`NebulaUserError.default(for:context:)`** — the shipped English fallback per
  ``NebulaError/Kind`` with HIG-neutral tone (no "you/your/we") and sensible recovery
  actions; overridable for L10n at the app layer.
- **`NebulaErrorConfiguration.withUserMessageMap(_:)`** — installs a `@Sendable`
  map `(NebulaError.Kind, [String: String]) -> NebulaUserError?`; default
  `{ _, _ in nil }` (opt-in).
- **`NebulaErrorConfiguration.userError(for:)`** — resolves an optional
  `NebulaUserError` for a ``NebulaError`` via the map (kind + metadata); **not**
  gated on `isEnabled`.
- **`NebulaErrorConfiguration`** — new `userMessageMap` stored property + `init`
  parameter (default `{ _, _ in nil }`); existing `.with*` builders pass it through
  unchanged.
- **`NebulaErrorConfig.userError(for:)`** — the process-wide accessor convenience
  (mirrors `report(_:)`).
- **`Tests/NebulaTests/ArchitectureUserErrorTests.swift`** — 21 tests / 5 suites:
  `RecoveryAction` equality/Hashable/description; `NebulaUserError` fields/equality/
  Hashable; the default table (all 8 kinds non-empty, HIG-neutral, `.unknown`→
  `[.dismiss]`, `.network`→retry+cancel, `.decoding`/`.serialization`/`.encoding`→
  `[.dismiss]`); config default→nil; `.withUserMessageMap` passes kind+metadata +
  preserves `isEnabled`/`category`/`handler`; `userError(for:)` not gated on
  `isEnabled`; the map can decline a kind (`nil`); `NebulaErrorConfig` accessor in a
  `@Suite(.serialized)` suite.

### Docs — Wave N12
- **`ArchitectureUserError.md`** (`Nebula.docc/`) — a guide-style article (the
  `ArchitectureErrors.md` model): the two-layer Apple error model; `NebulaUserError`
  as the value (not a `NebulaFailure`); `RecoveryAction` Nebula-authored;
  `.withUserMessageMap` mapping-only (no new `Kind` cases); the default English
  table + L10n at the app layer; `userError(for:)` orthogonal to reporting; what's
  refuted/deferred (`RecoveryURL`, `RecoverableError` conformance, presenter port).
- **`Architecture.md`** — `- <doc:ArchitectureUserError>` inserted after
  `- <doc:ArchitectureErrors>` (error topics clustered). The "Error taxonomy"
  paragraph is unchanged (the bridge adds no `Kind` case and no `NebulaFailure`
  conformer).

## [0.8.0] - 2026-07-20

> Nebula 0.8.0 — aligned to OS 26 (Liquid Glass). **Docs-only release:** a DocC
> composition-root recipe article, ``ArchitectureCompositionRoot``, that names what
> the existing "Dependency injection without a framework" paragraph leaves implicit —
> how to wire the full vertical (`viewmodel ← use case ← repository ← gateway ←
> cache`) at launch via explicit constructor injection of `Sendable` values,
> `NebulaRegistryConfig.set(…)` once, `.instrumented()` decorators, and a hand-off to
> the app's `@MainActor @Observable` viewmodel. **No new source types, no API change,
> no new tests** — the recipe's correctness is its fidelity to the existing
> `NebulaRegistry` / `NebulaUseCase` API. The article carries the guardrail "do not
> extend `NebulaRegistry` toward a container" (scope-creep risk #3) and the
> `@MainActor`-factory runtime-isolation caveat (Factory#322). The runnable
> `@MainActor @Observable` vertical is deferred to **N11b** in a sibling (Meridian) —
> forbidden in Foundation-only Nebula. 677 Nebula tests / 136 suites + 12 Aurora
> tests / 3 suites green (unchanged); zero concurrency warnings. DocC clean.

### Docs — Wave N11 (Composition root recipe)
- **`ArchitectureCompositionRoot.md`** (`Nebula.docc/`) — a guide-style article
  (the `ArchitecturePresentation.md` model: prose `###` subsections + a `## Topics`
  group of existing symbols, no new API). Sections: *Where the composition root
  lives* (at `@main`/`App.init`; `@MainActor` confined to the UI-owning root,
  services `nonisolated Sendable` cross via `await`; the runnable vertical is in the
  Meridian sibling); *Wiring order* (build `NebulaRegistryConfiguration` via
  `.withFactory(for:_:)`, `NebulaRegistryConfig.set(…)` once, resolve adapters,
  inject explicitly into the `NebulaUseCase` body, `.instrumented()`, hand off to
  the viewmodel); *Why not a container* (the guardrail — no singleton/scoping/graph;
  the registry is a factory map; no `NebulaCompositionRoot`/`NebulaAppContainer`
  helper type shipped); *The `@MainActor`-factory hazard* (keep registry factories
  `nonisolated @Sendable`; let the app do the actor hop). A `swift` wiring block
  stops at the use-case handoff — no SwiftUI/SwiftData symbols in Nebula's catalog.
- **`Architecture.md`** — `- <doc:ArchitectureCompositionRoot>` inserted after
  `- <doc:ArchitectureRegistry>` (registry → composition root → testing cluster).
  The "Dependency injection without a framework" paragraph is unchanged; the new
  article extends it, doesn't contradict it.

## [0.7.0] - 2026-07-20

> Nebula 0.7.0 — aligned to OS 26 (Liquid Glass). The interceptor seam + 401
> refresh-and-retry: a `Sendable` ``NebulaHTTPInterceptor`` port (`adapt`/`retry`)
> + `NebulaHTTPInterceptorChain` + `NebulaInterceptedClient` +
> `NebulaHTTPClient.intercepted(by:)` + a `NebulaTokenProvider` port + a concrete
> `NebulaAuthInterceptor` — **Nebula's first `actor`**, performing single-flight
> refresh (the first 401 refreshes; concurrent 401s `await` the same in-flight
> `Task`), bearer injection, and retry-once. The existing `NebulaRetry.withPolicy`
> cannot mutate the request between attempts, so a 401 cannot trigger a refresh +
> re-send through that seam — the interceptor port fills the gap. The interceptor
> is transparent: **no new `NebulaError.Kind` case** — it rethrows the client's
> errors and surfaces a refresh failure's app-supplied error in place of the 401.
> Foundation-only (pure stdlib actor + interceptors — no new framework import, no
> `#if os()`). 677 Nebula tests / 136 suites + 12 Aurora tests / 3 suites green;
> zero concurrency warnings under Swift 6 mode. Build-verified on all 5 platforms
> (iOS/macOS/tvOS/watchOS/visionOS); DocC clean.

### Added — Wave N10 (HTTP interceptors + 401 refresh-and-retry)
- **`NebulaHTTPInterceptor`** (`Architecture/Network/`) — a `Sendable` interceptor
  **port** with two phases: `adapt(_:)` (runs before every send; may transform the
  `NebulaHTTPEndpoint`) and `retry(_:for:attempt:)` (runs after a send throws;
  return a fresh endpoint to retry with, `nil` to decline, or throw to abort and
  surface that error). `attempt` is the retry index (`0` = first retry).
- **`NebulaHTTPInterceptorChain`** (`Architecture/Network/`) — a `Sendable` struct
  holding `[any NebulaHTTPInterceptor]` (derived `Sendable`, not `Equatable`).
  Composes `adapt` left-to-right, sends once, and on failure offers each
  interceptor a **single** retry chance built from the **original** endpoint (so an
  interceptor that wraps its input never double-wraps on retry).
  `CancellationError` is rethrown before the retry pass (never retried).
  `.withInterceptor(_:)` appends.
- **`NebulaInterceptedClient`** + **`NebulaHTTPClient.intercepted(by:)`**
  (`Architecture/Network/`) — a `Sendable` struct conforming to `NebulaHTTPClient`
  that routes `send` through a chain (forwarding `decoder`/`encoder`); the default
  extension `intercepted(by chain:)` / `intercepted(by [any NebulaHTTPInterceptor])`
  wires it in. The verb conveniences (`get`/`post`/…) funnel through unchanged.
- **`NebulaTokenProvider`** (`Architecture/Network/`) — the **port** the app
  conforms to supply credentials: an `associatedtype Token: Sendable`;
  `currentToken() async throws -> Token?` (`nil` = anonymous passthrough);
  `refresh() async throws -> Token` (app-supplied error on failure);
  `authorizationHeader(for:) -> String` (e.g. `"Bearer <jwt>"`). PAT so the
  concrete interceptor is generic over a concrete `Token`.
- **`NebulaAuthInterceptor<Provider>`** (`Architecture/Network/`) — the concrete
  ``NebulaHTTPInterceptor`` and **Nebula's first `actor`**. `adapt` injects
  `Authorization: Bearer <token>` (anonymous passthrough when there is no
  session); `retry` matches the 401 `NebulaError` that `NebulaHTTPGateway` surfaces
  (domain `"Nebula.HTTP"`, code `401`) at `attempt == 0`, refreshes **single-
  flight** via an actor-isolated `Task<Token, any Error>?`, and returns the
  endpoint re-adapted with the new token. Retry-once cap (a second 401 surfaces).
  The header is injected at the `URLRequest` layer via a private endpoint
  wrapper, which works because `NebulaHTTPGateway.buildRequest` only fills config
  headers for fields the endpoint did not set. The actor's mutable state is
  isolated (no `@unchecked`); the actor is implicitly `Sendable`.
- **Tests** — `ArchitectureAuthTests` (15): the chain (empty forwards,
  adapt-once-per-send, `CancellationError` not retried, declined-retry surfaces
  the original 500); `adapt` (injects `Bearer <current>`, nil-token anonymous
  passthrough, forwards `cachePolicy`); 401 (401-then-200 refreshes once + retries
  with the new token + sends==2, non-401 (500) not retried, second-401 surfaces
  with no infinite loop, refresh-failure surfaces the provider error);
  concurrency `@Suite(.serialized)` (two concurrent 401s share **one** refresh —
  `refreshCount==1`, sends==4; 50 concurrent always-200 → no refresh, all
  succeed); `intercepted` (verbs funnel the header through, two interceptors
  compose left-to-right). No network / no `URLProtocol` — a behavior-driven fake
  `NebulaHTTPClient`.
- **DocC** — `ArchitectureAuth.md` (indexed in `Architecture.md` after
  `ArchitectureHTTPServer`, network cluster). Error-taxonomy paragraph unchanged
  (N10 adds no error type).

## [0.6.0] - 2026-07-19

> Nebula 0.6.0 — aligned to OS 26 (Liquid Glass). The secure-storage seam: a
> `Sendable` key-value port (`NebulaSecureStore`) plus a stateless `final class`
> façade over the Security.framework `SecItem*` C API (`NebulaKeychain`), the
> first wave under the resolved "non-UI Apple system frameworks" scope
> (`import Security` in-bounds). Unlike `NebulaDefaults` (which wraps a
> non-`Sendable` `UserDefaults` object in a `Mutex`), the Keychain C API has no
> Swift object to region-isolate — it is thread-safe free functions over an
> immutable `Sendable` config — so `NebulaKeychain` derives `Sendable` with **no
> `Mutex` and no `@unchecked`** (the `NebulaError.Box` precedent). `errSec*`
> OSStatus codes bridge to the existing `NebulaError.Kind.cocoa` (no new `Kind`
> case). 662 Nebula tests / 131 suites + 12 Aurora tests / 3 suites green; zero
> concurrency warnings under Swift 6 mode. Build-verified on all 5 platforms
> (iOS/macOS/tvOS/watchOS/visionOS); DocC clean.

### Added — Wave N9 (secure storage: Keychain façade + port)
- **`NebulaSecureStore`** (`Architecture/Keychain/`) — a `Sendable` secure-storage
  **port** with three byte-level requirements, each `throws`:
  `data(forKey:)` (returns `nil` for an absent key, `throws` for a genuine
  failure — auth failed, device locked, missing entitlement — so a caller can
  distinguish "no secret" from "could not read the secret"), `setData(_:forKey:)`
  (removes the key when `nil`), and `remove(forKey:)`. A **default extension**
  gives every conformer a `Codable` bridge (`value(_:forKey:)` /
  `setValue(_:forKey:)` — JSON through `Data`, per-call coders decoupled from the
  gateway's `NebulaJSONEncoder`/`NebulaJSONDecoder`) and a `RawRepresentable`
  bridge (`rawValue(_:forKey:)` / `setRawValue(_:forKey:)`, `RawValue: Codable`).
  Distinct from `NebulaPreferences` — secrets and user-tunable preferences have
  different threat models; an app injects a secure store and a preferences store
  as separate seams.
- **`NebulaKeychain`** (`Architecture/Keychain/`) — the concrete **stateless
  `final class`** façade over `SecItemAdd` / `SecItemCopyMatching` /
  `SecItemUpdate` / `SecItemDelete`. Holds an immutable `let config:
  NebulaKeychainConfig`; `Sendable` is **derived** (a `final class` with a single
  `let` `Sendable` property — the `NebulaError.Box` precedent, not the
  `NebulaDefaults` `Mutex` precedent), so a single instance is safe to share
  across tasks. Fresh query dict per call; `setData` updates an existing item in
  place first (`SecItemUpdate`), falling back to `SecItemAdd` only on
  `errSecItemNotFound` (preserves access control, avoids a re-prompt);
  `errSecInteractionNotAllowed` (device locked) is non-destructive — no path
  deletes on this error; `remove` is idempotent (`errSecItemNotFound` is a no-op
  success).
- **`NebulaKeychainConfig`** (`Architecture/Keychain/`) — a `Sendable` /
  `Equatable` value: `service` (required), `accessGroup`? (an app-level
  entitlement — Nebula exposes the seam only), `accessible`, and
  `useDataProtectionKeychain` (default `true` — the modern cross-platform
  keychain). Fluent `.withService` / `.withAccessGroup` / `.withAccessible` /
  `.withUseDataProtectionKeychain` builders. No `static let default` (a `service`
  is required); no process-wide `Mutex` accessor (the caller owns the instance).
- **`NebulaKeychainAccessible`** (`Architecture/Keychain/`) — a `Sendable` /
  `Equatable` / `Hashable` enum mapping 1:1 to the `kSecAttrAccessible*`
  `CFString` constants (`whenUnlocked` / `afterFirstUnlock` /
  `whenPasscodeSetThisDeviceOnly` / `whenUnlockedThisDeviceOnly` /
  `afterFirstUnlockThisDeviceOnly`). All 5-platform — no `@available` gates.
- **`NebulaKeychainError`** (`Architecture/Keychain/`) — a per-layer open struct
  `: NebulaFailure, Equatable, Hashable` (mirrors `NebulaRepositoryError` /
  `NebulaHTTPServerError`). Open-struct `Kind` with presets `itemNotFound` /
  `duplicateItem` / `authFailed` / `interactionNotAllowed` /
  `missingEntitlement` / `cancelled` / `unknown`. Stores the raw `OSStatus`
  (`Int32`, trivially `Sendable` — not boxed). `coarseKind`:
  `duplicateItem` / `authFailed` / `interactionNotAllowed` / `missingEntitlement`
  → `.cocoa` (the CoreFoundation/OSStatus bucket); `itemNotFound` / `cancelled`
  / `unknown` → `.unknown`. Bridges via `toNebulaError(kind:)` (writes
  `NebulaCode` + `NebulaOSStatus` metadata) — picked up by the existing
  `as? NebulaFailure` dispatch in `NebulaError(error:)`; **no new
  `NebulaError.Kind` case**.
- **Tests** — `ArchitectureKeychainTests` (27): the error struct (presets,
  `ExpressibleByStringLiteral`, `defaultCode`, factory status, `coarseKind`,
  `toNebulaError` preserves domain+code+OSStatus, `NebulaError(error:)` dispatch,
  equality+hashable, Sendable compile proof, `#expect(throws: target)`); the port
  seam (an `InMemorySecureStore` `final class` `Mutex<[String: Data]>` conformer
  proving the Codable/RawRepresentable default extension is reusable); real
  macOS host Keychain integration (`@Suite(.serialized)`, unique service per test
  + `defer` cleanup, no stub); Sendable + 50-task concurrency.
- **DocC** — `ArchitectureKeychain.md` (indexed in `Architecture.md` after
  `ArchitecturePreferences`); `NebulaKeychainError` added to the error-taxonomy
  paragraph.

### Fixed — test stability (pre-existing, surfaced by N9)
- `MeasureTests.swift` `NebulaMeasureConfigTests` — the two process-wide-accessor
  tests raced on the shared `NebulaMeasureConfig` under Swift Testing's default
  parallelism (one test's `defer { set(.default) }` could land between the
  other's `set(custom)` and its `get().bench()`, so `bench` fired the default
  no-op handler). Marked `@Suite(.serialized)`. No production-behavior change.

## [0.5.0] - 2026-07-19

> Nebula 0.5.0 — aligned to OS 26 (Liquid Glass). The proper network layer:
> Endpoint / Client / Request / Response model (`NebulaHTTPEndpoint` /
> `NebulaHTTPRequest` / `NebulaHTTPResponse` / `NebulaHTTPClient` — non-generic,
> existential-friendly; verbs as default extensions, backward-compatible) + a
> per-endpoint cache (Nebula TTL / stale-while-revalidate metadata over the native
> `URLCache` — "Ambos") + a simple local HTTP/1.1 server over Network.framework
> (`NebulaHTTPServer` / `NWListener`). This release also folds in the previously-
> unreleased N1–N3 surface (retry / preferences / Aurora SwiftData); the 0.4.0
> milestone was not tagged separately. 635 Nebula tests / 127 suites + 12 Aurora
> tests / 3 suites green; zero concurrency warnings under Swift 6 mode.
> Build-verified on all 5 platforms (iOS/macOS/tvOS/watchOS/visionOS); DocC clean.

### Added — Wave N3 (persistence: Aurora sibling package — SwiftData)
- **`Aurora`** — a new local SwiftPM package (`Aurora/`, path-dep on Nebula,
  mirroring Meridian) that ships the SwiftData persistence adapter. The
  separation is load-bearing: `import Aurora` from inside Nebula is a **hard
  compile error** (Nebula's manifest is `dependencies: []` with no target
  depending on Aurora), so the Clean Architecture dependency rule — domain and
  use cases never import persistence — is compiler-enforced across packages.
  SwiftData is a system framework (not an SPM dep), so Aurora stays
  third-party-free. Versioning: Aurora N ↔ Nebula N ↔ OS N (policy finalized at
  N4, mirroring Meridian N ↔ Nebula N ↔ OS N).
- **`AuroraEntityMapping`** (`Aurora/Sources/Aurora/`) — a **type-level** protocol
  (static methods) bridging a SwiftData `@Model` (`PersistentModel`) to a Nebula
  `NebulaEntity` DTO: `toEntity` / `insert(_:in:)` / `update(_:from:)` /
  `descriptor(for:)` / `descriptor()`. Type-level so the repository holds no
  per-instance mapping state. The app conforms it per `@Model` type with a
  caseless `enum: AuroraEntityMapping, Sendable`.
- **`AuroraRepository<Mapping>`** (`Aurora/Sources/Aurora/`) — a `@ModelActor`
  `actor` generic over `Mapping: AuroraEntityMapping & Sendable`, conforming to
  `NebulaRepository` + `NebulaReadOnlyRepository` + `NebulaKeyedRepository` +
  `NebulaWritableRepository` + `NebulaDeletableRepository` (`Element =
  Mapping.Entity`). `@ModelActor` synthesizes the actor-isolated `ModelContext`
  and `init(modelContainer:)`. `stream()` is `nonisolated` (the port returns an
  `AsyncThrowingStream`, not `async`) and spawns a `Task` that hops to the actor;
  `count()` / `find(id:)` / `save(_:)` / `delete(_:)` are `async` on the actor.
  SwiftData's `@Model`/`ModelContext` are not `Sendable` (verified); the mapping
  bridges them to the `Sendable` `NebulaEntity` DTO so nothing non-`Sendable`
  escapes. SwiftData errors are rethrown untyped (Nebula's public-API posture).
- **`AuroraExample`** — a runnable end-to-end demo (`@Model` + `NebulaEntity` +
  mapping + in-memory `ModelContainer` + `AuroraRepository` CRUD round-trip);
  `swift run AuroraExample` is the N3 gate. Not a shipped product.
- Tests: `AuroraTests/AuroraRepositoryTests.swift` (12) — save (insert +
  add-or-replace by id), find (present/absent), count, stream (all/empty),
  delete (present/absent-no-op), port-conformance for all four capability ports
  (assign-to-existential + cast-back), Sendable-across-`Task`. 12 Aurora tests /
  3 suites green; zero concurrency warnings; release clean. Aurora has no
  `#if os()` (SwiftData + Foundation only).

### Added — Wave N2 (preferences: NebulaPreferences + NebulaDefaults)
- **`NebulaPreferences`** (`Architecture/Preferences/`) — a `Sendable` key-value
  preferences port: three byte-level requirements (`data(forKey:)` /
  `setData(_:forKey:)` / `remove(forKey:)`) plus a **default extension** that
  gives every conformer a `Codable` bridge (`value(_:forKey:)` /
  `setValue(_:forKey:)`, JSON through `Data`) and a `RawRepresentable` bridge
  (`rawValue(_:forKey:)` / `setRawValue(_:forKey:)`, `RawValue: Codable`). The
  seam is tiny on purpose — a test double, an iCloud key-value store, or an
  encrypted store conforms by implementing three methods and inherits the typed
  ergonomics. The Codable bridge uses plain `JSONEncoder`/`JSONDecoder` (Sendable,
  per-call), decoupled from the gateway's encoder configuration. Reads are
  lenient (`T?`, `nil` = absent, throws on corrupt); writes throw on encode;
  `setValue(nil)` / `setRawValue(nil)` removes the key.
- **`NebulaDefaults`** (`Architecture/Preferences/`) — the concrete
  `NebulaPreferences` façade over `UserDefaults`. `UserDefaults` is thread-safe
  but `@_nonSendable(_assumed)` in Swift 6, so it is wrapped in a
  `Mutex<UserDefaults>` (region-based isolation, the alternative to
  `@unchecked`) inside a `final class` that absorbs the `~Copyable` `Mutex`
  behind a copyable, `Sendable` reference (derived, **no `@unchecked`**). The
  initializer takes the `UserDefaults` `sending` (SE-0430) — ownership transfers
  at the call site, so the compiler rejects further use of that instance (no two
  regions racing on the same non-`Sendable` store).
- Tests: `ArchitecturePreferencesTests.swift` (17) — byte-level round-trip,
  Codable round-trip + absent→nil + corrupt→`DecodingError`, RawRepresentable
  String/Int round-trip + unmappable-raw→nil, an `InMemoryPrefs` `final class`
  proving the default extension works on a non-`UserDefaults` conformer, an
  existential holding both impls, and a Sendable-across-`Task` + 50-task
  concurrent-access smoke test. 574 tests / 118 suites green (+17 over N1); zero
  concurrency warnings under Swift 6 mode. New code has no `#if os()` (Foundation
  + Synchronization only).

### Added — Wave N1 (network: NebulaHTTPGateway + NebulaRetry)
- **`NebulaRetryPolicy` / `NebulaRetry` / `NebulaRetryJitter`** (`Architecture/Async/`) — a
  framework-agnostic retry loop for any `async throws` operation. `NebulaRetryPolicy` is a
  `Sendable` value (NOT `Equatable` — it stores a `@Sendable` `isRetriable` predicate, mirroring
  `NebulaGatewayConfiguration`): `maxAttempts` (total, including the first; clamped to ≥ 1),
  `baseDelay`, `multiplier`, `maxDelay`, `jitter` (`.none`/`.full`/`.equal`), and the predicate.
  `delay(forFailedAttempt:)` = `baseDelay * multiplier^index`, capped at `maxDelay`, then
  jittered. `NebulaRetry.withPolicy(_:sleeper:operation:)` retries on errors the predicate
  accepts, honors cancellation (`Task.checkCancellation()` before each attempt; a thrown
  `CancellationError` is never retried; a cancellation during `sleeper` propagates out), and
  rethrows the original error on exhaustion / for non-retriable errors. `sleeper` is injectable
  for tests (default `Task.sleep(for:)`). `defaultIsRetriable` retries transient `URLError`
  codes (`.timedOut`/`.cannotConnectToHost`/`.networkConnectionLost`/`.notConnectedToInternet`/
  `.dnsLookupFailed`/`.cannotFindHost`) + HTTP 408/429/500/502/503/504.
- **`NebulaHTTPGateway`** (`Architecture/Gateway/`) — the concrete `NebulaGateway` over
  `URLSession` the Wave H scaffold was built for. Foundation-only (no new framework import).
  `get`/`post`/`put`/`delete` (decode `T` or raw `Data`); reuses `NebulaGatewayConfiguration`'s
  `NebulaJSONDecoder`/`NebulaJSONEncoder`; retries via `NebulaRetry.withPolicy`; bridges
  `URLError` + HTTP status failures to `NebulaError` (kind `.network`, code domain
  `Nebula.HTTP`/`NSURLErrorDomain`) and reports them through the config's `handler`.
  `Sendable` derived (config + `URLSession` + policy all `Sendable` — no `@unchecked`).
- **`NebulaHTTPStatusError`** (`Architecture/Gateway/`) — `Error`/`Sendable`/`Equatable`
  carrying an HTTP status code, so the retry predicate distinguishes "transport failed"
  (`URLError`) from "server answered with an error status" and retries 5xx/408/429 selectively.
- Tests: `ArchitectureRetryTests.swift` (16) + `ArchitectureHTTPGatewayTests.swift` (13, over a
  `URLProtocol`-backed `URLSession` — no real network). 557 tests / 113 suites green (+32 over
  0.3.0); zero concurrency warnings under Swift 6 mode. New code has no `#if os()` (Foundation +
  Synchronization only).

### Added — Wave N7 (network: local HTTP server — Network.framework)
- **`NebulaHTTPServer`** (`Architecture/Network/`) — a simple local HTTP/1.1 server, the
  server-side counterpart to `NebulaHTTPGateway`. A `final class: Sendable` over `NWListener` /
  `NWConnection` (Network.framework — Foundation + Network, no SwiftUI / UIKit / new framework
  import). Listens on a TCP port, accepts connections, parses each request via
  `NebulaHTTPRequestParser` into a `NebulaHTTPRequest` (the **same value type the client
  builds**), dispatches it to a `@Sendable` handler, and writes the handler's `NebulaHTTPResponse`
  back as HTTP/1.1 bytes. Each connection runs in a `Task` (the callback-based `receive` / `send`
  are async-wrapped via `withCheckedContinuation`) and is closed after one response. `Sendable` is
  derived — `NWListener`, `NWConnection`, the `@Sendable` handler, and `DispatchQueue` are all
  `Sendable` at the `.v26` floor (no `@unchecked`); the one shared mutable state (the start-once
  flag) is a `Mutex`-guarded `final class` `OnceFlag` so `start()` resumes its continuation exactly
  once. `init(port:handler:)` (default 8080; pass `NWEndpoint.Port(rawValue: 0)` for an
  OS-assigned ephemeral port, then read `port` after `start()`), `start() async throws`
  (throws `NebulaHTTPServerError.bindFailed` if the port cannot bind), `stop()`. Scope is
  deliberately **"simple"**: plain HTTP/1.1, no TLS, no chunked transfer-encoding, no keep-alive
  (close after one response), `Content-Length` bodies only — a dev / test / full-stack-app tool,
  not a production server.
- **`NebulaHTTPRequestParser`** (`Architecture/Network/`, internal) — a bounded HTTP/1.1
  request parser (request line + headers + a `Content-Length` body, hand-rolled — no third-party
  dep). Returns `nil` when the buffer does not yet contain a complete request (the caller reads
  more and retries); throws `NebulaHTTPServerError.parseFailed` on malformed input. **Rejects
  negative, non-numeric, and oversized (`> 10 MiB`) `Content-Length` up front** — a negative value
  would otherwise build a reversed `Range` in `subdata(in:)` and trap the process (a crafted
  request must not crash the server). `maxBodyLength = 10 * 1024 * 1024`.
- **`NebulaHTTPServerError`** (`Architecture/Network/`) — the per-layer server error: a bind /
  parse / send failure surfaced by `NebulaHTTPServer`. An open-struct `Kind`
  (`bindFailed`/`parseFailed`/`sendFailed`/`cancelled`/`unknown`, `ExpressibleByStringLiteral`)
  plus a fine free-form `code`, conforming to `NebulaFailure, Equatable, Hashable` (mirrors
  `NebulaRepositoryError`). `coarseKind` maps bind/send → `.network`, parse → `.decoding`,
  cancelled/unknown → `.unknown`; `toNebulaError(kind:)` bridges to the closed `NebulaError.Kind`
  (no new `Kind` case). `NWError` is **not** `Sendable`, so it is never boxed across isolation —
  its description is folded into `message` (lossy, mirroring the gateway's `URLError` bridging).
- Serializer hardenings — `NebulaHTTPServer.serialize(_:)` overwrites any handler-provided
  `Content-Length` (case-insensitive) with the actual body count (no duplicate / stale header) and
  strips `\r\n` from handler-provided header names and values so a misbehaving handler cannot
  inject extra headers or a body.
- Tests: `ArchitectureHTTPServerTests.swift` — parser (complete GET / query items / POST body /
  incomplete headers→nil / incomplete body→nil / malformed request line / unsupported method /
  negative / non-numeric / oversized `Content-Length`), serializer (status line + headers + body,
  reason phrases, case-insensitive `Content-Length` overwrite, `\r\n` strip), error
  (`coarseKind` mapping, `toNebulaError` preserves kind+code, `NebulaError(error:)` dispatch,
  equality), and a **real localhost round-trip** (`NebulaHTTPServer` + `NebulaHTTPGateway` over
  `URLSession` — no `URLProtocol` stub; `@Suite(.serialized)`, OS-assigned ephemeral port): GET
  round-trip, POST echo, 404 → `NebulaError` `.network`, query items reach the handler.

### Added — Wave N6 (network: per-endpoint cache — Nebula over native URLCache)
- **`NebulaHTTPCachePolicy`** (`Architecture/Network/`) — the per-endpoint cache policy:
  `protocolDefault` (delegate to `URLSession`'s native HTTP cache), `bypass` (skip caching
  entirely), `store(ttl:)` (cache fresh for `ttl`), `staleWhileRevalidate(ttl:maxStale:)` (cache
  fresh for `ttl`, then serve stale within `maxStale` while revalidating in the background). A
  `Sendable, Equatable, Hashable` enum; defaulted on `NebulaHTTPEndpoint` to `.protocolDefault`,
  overridable per request.
- **`NebulaHTTPCache`** (`Architecture/Network/`) — the cache **port**: a `Sendable` collaborator
  the gateway consults before a network fetch and stores into after one. `response(for:policy:)`
  returns a `NebulaCachedResponse` (a response paired with `isStale`) or `nil`; `store`,
  `remove(for:)`, `removeAll`. The `isStale` flag lets the gateway serve a stale hit immediately
  and revalidate in a background `Task` only when the entry is actually stale, not on every fresh
  hit. Nebula owns the TTL / stale-while-revalidate **metadata**; a concrete façade holds the
  response **bytes**.
- **`NebulaURLCache`** (`Architecture/Network/`) — the concrete `NebulaHTTPCache` façade over the
  native `URLCache` ("Ambos — Nebula sobre nativo"): a `final class` wrapping `Mutex<State>`
  where `State` holds the native `URLCache` plus Nebula's metadata map (one lock so a hit reads
  both atomically and a store writes both atomically). `URLCache` is thread-safe but **not
  `Sendable`** in Swift 6 (verified against the Xcode 27 Beta 3 `.swiftinterface` — only a
  convenience `init` extension, no `Sendable` conformance), so the `Mutex` provides the
  synchronization boundary (region-based isolation, the alternative to `@unchecked`) and the
  `final class` derives `Sendable` with **no `@unchecked`** (the `NebulaDefaults` / `NebulaSpyUseCase`
  precedent). `init(_ cache: sending URLCache = .shared)` (SE-0430 — ownership transfers at the
  call site). Fresh within TTL; stale within `ttl + maxStale` (returns `isStale == true`); beyond
  that, `nil`. Orphaned metadata is cleaned up if the native cache evicted the bytes.
- **Gateway `send` integration** — `NebulaHTTPGateway` gains an optional `cache: NebulaHTTPCache?`
  constructor arg (default `nil` — no Nebula caching; `URLSession`'s native protocol cache still
  applies) and a `withCache(_:)` builder. When a cache is injected, `buildRequest` sets
  `URLRequest.cachePolicy = .reloadIgnoringLocalCacheData` for `.store` / `.staleWhileRevalidate`
  so **Nebula's TTL wins over the native cache** (Nebula is authoritative). `send` consults the
  cache for cacheable policies: a fresh hit returns without a network fetch; a stale hit returns
  the stale response **and** kicks a `Task.detached` background revalidate-and-store (detached, not
  `Task {}`, so a `@MainActor` consumer does not get the store hopping to main); a 2xx response is
  stored. `.protocolDefault` / `.bypass` skip the Nebula cache.
- Tests: `ArchitectureHTTPCacheTests.swift` (10) — store→fresh, miss when nothing stored, expired
  →nil (1 ms TTL), stale-while-revalidate returns stale within `maxStale`, stale beyond `maxStale`
  →nil, `remove` drops an entry, `removeAll` drops everything, `protocolDefault` / `bypass` are
  not Nebula-managed, `store` declines for a non-Nebula-managed policy (dedicated in-memory
  `URLCache` per test, `@Suite(.serialized)`) + 5 gateway cache integration tests in
  `ArchitectureHTTPGatewayTests` (fresh hit skips network, cache miss fetches + stores, bypass
  skips cache, stale hit serves + revalidates in the background, store policy without a cache still
  fetches).

### Added — Wave N5 (network: Endpoint / Client / Request model + gateway refactor)
- **`NebulaHTTPMethod`** (`Architecture/Network/`) — `enum: String, Sendable, Equatable, Hashable`
  (get / post / put / patch / delete / head).
- **`NebulaHTTPEndpoint`** (`Architecture/Network/`) — the **port**: a `Sendable` type that
  builds a `URLRequest` against a base URL (`func urlRequest(against baseURL: URL?) throws ->
  URLRequest` — the `URLRequestConvertible` idea). Non-generic so `any NebulaHTTPEndpoint` is a
  usable existential. `cachePolicy` is a default extension (`.protocolDefault`), overridable by
  conformers — a protocol requirement, not just a default extension, so existential
  witness-table dispatch honors a conformer's override.
- **`NebulaHTTPRequest`** (`Architecture/Network/`) — the concrete **value type**
  (`struct: NebulaHTTPEndpoint, Sendable, Equatable`): `method` / `path` / `query:
  [URLQueryItem]` / `headers: [String: String]` / `body: NebulaHTTPBody` / `cachePolicy`.
  `urlRequest(against:)` resolves the URL (relative → baseURL, absolute path, query appended not
  replaced — replicates the Wave N1 resolution so existing tests pass). **Reused as the
  server-side parsed-request type** — the client and the local server share one request shape.
- **`NebulaHTTPBody`** (`Architecture/Network/`) — `enum: Sendable, Equatable { none, data(Data,
  contentType:), static func json(_:using:) throws }`. `.json` encodes **eagerly** so the value
  stays `Sendable` (the `Encodable` is consumed, not stored).
- **`NebulaHTTPResponse`** (`Architecture/Network/`) — `struct: Sendable, Equatable { statusCode,
  headers, body: Data }` + a generic `decode<T: Decodable & Sendable>(_:using:)`.
- **`NebulaHTTPClient`** (`Architecture/Network/`) — the **client port**: `protocol
  NebulaHTTPClient: NebulaGateway` with `send(_ endpoint:) async throws -> NebulaHTTPResponse` as
  the one transport requirement (non-generic, existential-friendly — the Point-Free `send(_:)->
  Response` shape; the [[nebula-aurora-swiftdata]] work proved `associatedtype`-returning methods
  cannot be called on `any` existentials under Swift 6.2). Default extensions: `send<T: Decodable
  & Sendable>(_:as:)` (decode) + the **verb conveniences** (`get` / `get(_:as:)` / `post` /
  `put` / `delete`) building a `NebulaHTTPRequest` and delegating to `send` — **preserving the
  Wave N1 verb signatures** so call sites are backward-compatible. The codec requirements let the
  verbs use the configured `NebulaJSONEncoder` / `Decoder` (configure-once-and-freeze preserved).
- **`NebulaHTTPGateway` refactor** (`Architecture/Gateway/`) — now conforms to `NebulaHTTPClient`.
  The verb methods move off the struct onto the `NebulaHTTPClient` default extension; the struct's
  one new requirement is `send(_:)`. `send`: `buildRequest` (endpoint → `URLRequest`, merge config
  headers for keys the request didn't set — **per-request headers override config defaults**;
  apply config `timeout`; map `cachePolicy` → `URLRequest.cachePolicy`) → `NebulaRetry.withPolicy`
  around `session.data(for:)` → `validate` (2xx) → `NebulaHTTPResponse`. Error bridging unchanged
  (`NebulaHTTPStatusError` / `URLError` / fallback → `NebulaError` kind `.network`, reported via
  `configuration.report(_:)`; no new `Kind` case).
- Tests: `ArchitectureNetworkTests.swift` — endpoint → `URLRequest` building (relative / absolute
  / query / headers / body / cache policy), response `decode`, client `send(_:as:)` decode + the
  verb conveniences; existing `ArchitectureHTTPGatewayTests` pass unchanged (verb signatures
  preserved).

### Added — Wave N8 (governance — DocC + ADR + final gate)
- DocC articles `ArchitectureNetwork.md` / `ArchitectureHTTPCache.md` / `ArchitectureHTTPServer.md`
  (indexed in `Architecture.md` after `ArchitectureGateway`); ADR in `DECISIONS.md`
  (Network layer, Waves N5–N8, Accepted); `ARCHITECTURE.md` `Network/` subtree row + structure tree
  + Data + Network prose; this roadmap. Vault `03-padroes/nebula-network-endpoint-client.md`
  marked `status: shipped` / `shipped: "0.5.0"`; `vault/Home.md` index updated.
- Tests: 635 Nebula tests / 127 suites green (+61 over N3's 574 / 118); zero concurrency warnings
  under Swift 6 mode. New code has no `#if os()` (Foundation + Network + Synchronization only).
  Release clean; build-verified on all 5 platforms (iOS/macOS/tvOS/watchOS/visionOS); DocC
  `xcodebuild docbuild` succeeds (new articles resolve).

## [0.3.0] - 2026-07-19

> Nebula 0.3.0 / Meridian 0.3.0 — aligned to OS 26 (Liquid Glass). Presentation
> architecture: MVVM `@Observable` + native typed-`[Route]` Router (no Coordinator
> tree), shipped as Foundation-only seams in Nebula + a sibling **Meridian**
> SwiftPM package that owns SwiftUI. `import Meridian` from Nebula is a hard
> compile error → the Clean Architecture dependency rule is compiler-enforced
> across packages. The `NebulaRouter` port is **async** so the `@MainActor
> @Observable` Meridian `Router` conforms while Nebula stays `@MainActor`-free.
> 525 Nebula tests / 13 Meridian tests green; zero concurrency warnings under
> Swift 6 mode. Build-verified on all 5 platforms (iOS/macOS/tvOS/watchOS/visionOS).

### Added — Wave I (presentation architecture, Foundation-only seams)
- **Architecture/Presentation** — the Foundation-only presentation half of the
  data-driven `Router` pattern (the sibling **Meridian** package, Wave II, owns
  the `@Observable Router` + `NavigationStack` wiring). Five symbols, all pure
  `import Foundation` (+ `import Synchronization` for the spy):
  - `NebulaRoute` — `protocol: Hashable, Sendable, Codable`; the route contract
    an app's `Route` enum conforms to (push identifier values, render models).
  - `NebulaNavigationStack<Route>` — a typed `[Route]` navigation **model** as a
    `Sendable`/`Codable`/`Equatable` value type: `push`/`pop`/`popToRoot`/
    `replaceStack`. Stack logic in `static func …(into: inout [Route])` — single
    source of truth shared by the instance API and (Wave II) the `@Observable`
    Router. Deep links = "build `[Route]`, `replaceStack`" — pure data, testable
    without a simulator. Typed `[Route]` preferred over type-erased
    `NavigationPath` (compile-time exhaustive handling, inspectable/reorderable
    stack — defensive vs `NavigationStack`'s reported macOS bugs, risk #4).
  - `NebulaRouter<Route>` — the navigation-intent **port**, primary associated
    type `Route` (SE-0346), `Sendable`, with **`async`** requirements
    (`push`/`pop()`/`pop(_:)`/`popToRoot`/`replaceStack`). Async is the Swift 6
    way to let a `@MainActor @Observable` concrete `Router` (Meridian) satisfy a
    nonisolated, Foundation-only port: a synchronous `@MainActor` method witnesses
    a nonisolated `async` requirement (the `await` hops to the main actor), so
    Nebula stays free of `@MainActor` (app supplies isolation) yet the on-actor
    router conforms. The async port is also the cross-actor bridge for off-actor
    deep-link parsers. Conformers keep **synchronous** implementations (a sync
    method witnesses an async requirement) — concrete calls stay sync.
  - `NebulaViewModel` — bare `Sendable` marker; Nebula ships **only the marker**
    (NOT `@Observable` — Swift 6 friction outside SwiftUI; the consumer adds
    `@MainActor @Observable`).
  - `NebulaSpyRouter<Route>` — spy router recording every intent as a value
    (`Intent` enum `Sendable`/`Equatable`); `final class` + `let Mutex`,
    `Sendable` **derived** (no `@unchecked`), mirroring `NebulaSpyUseCase`.
    Conforms to `NebulaRouter` — a drop-in substitute for the port in tests.
- Tests: `ArchitecturePresentationTests.swift` — navigation model ops, deep-link
  `replaceStack`, `Codable` round-trip (state restoration), `Sendable`-across-
  tasks, spy intent recording, and port-conformance through `any NebulaRouter<R>`.
  525 tests / 110 suites green (+16 over 0.2.0); zero concurrency warnings under
  Swift 6 mode. New files have no `#if os()` (Foundation + Synchronization only).

### Added — Wave II (Meridian, the presentation-architecture sibling package)
- **`Meridian/`** — a NEW separate local SwiftPM package (its own `Package.swift`,
  module graph, and DocC catalog) in this repo, depending on Nebula via
  `.package(name: "Nebula", path: "../")`. Where Nebula is Foundation-only,
  Meridian swallows SwiftUI. `swift-tools-version: 6.3`, language mode v6, all 5
  platforms `.v26`, `defaultLocalization: en`; `dependencies` lists only the local
  Nebula sibling (SwiftUI is a system framework, not an SPM dep) → third-party-free.
  One repo / one CI lane builds both; promoting Meridian to its own git repo for
  public consumption is a documented future step (the `path` dep becomes a URL).
  The separation is load-bearing: `import Meridian` from inside Nebula is an
  **unconditional hard compile error** (Nebula `dependencies: []`), so the Clean
  Architecture dependency rule (use cases/domain never import presentation) is
  compiler-enforced across packages — closing the Wave H open risk (SR-1393 only
  applies within one package's shared `.build`). Mirrors `swift-navigation`.
- `Router<Route: NebulaRoute>` — `@MainActor @Observable final class` conforming to
  `NebulaRouter<Route>`; owns the observation-tracked `var path: [Route]`; intent
  methods (`push`/`pop()`/`pop(_:)`/`popToRoot`/`replaceStack`) delegate to
  `NebulaNavigationStack` statics (single source of truth shared with the pure-Swift
  model). `Sendable` by `@MainActor` isolation (no `@unchecked`). The data-driven
  Router pattern — one per tab — NOT a Coordinator tree (owner preference).
- `MeridianNavigationStack<Route, Root, Destination>` — a `View` wiring
  `NavigationStack(path: $router.path)` + `navigationDestination(for: Route.self)`
  with a `@ViewBuilder` destination resolver (the type-driven view factory).
- **Async port conformance fix**: `NebulaRouter`'s requirements are `async`
  (Wave I) precisely so this `@MainActor` `Router` can conform to a nonisolated,
  Foundation-only port — a synchronous `@MainActor` method witnesses a nonisolated
  `async` requirement (the `await` hops to the main actor). Nebula stays free of
  `@MainActor`; the async port doubles as the cross-actor bridge for off-actor
  deep-link parsers. Conformers keep sync impls — concrete calls stay synchronous.
- Tests: `Meridian/Tests/MeridianTests/RouterTests.swift` — push/pop/replaceStack
  as data, deep-link, port-conformance through `any NebulaRouter<R>` (async hop),
  `@MainActor` Sendable, `Codable` path round-trip. 6 tests / 1 suite green; zero
  concurrency warnings. `@Suite @MainActor` (constructing `Router` requires the
  main actor).

### Added — Wave III (destinations + deep-link + example)
- **`MeridianExample`** — a runnable executable target demonstrating the full
  pattern: `Router<AppRoute>` + `MeridianNavigationStack` + a type-driven
  `Destination` enum driving `sheet(item:)` ("impossible states unrepresentable")
  + an `onOpenURL` deep-link handler. `@main App`; compiling it is the Wave III
  gate; `swift run MeridianExample` launches the macOS app. NOT a shipped product.
- **Type-driven destinations** (pattern): a single `Optional<Destination>` enum
  per feature drives `sheet(item:)` — only one destination active, compiler-
  enforced (no `@CasePathable` macro — `dependencies: []`; `Identifiable` hand-
  rolled). Documented in `Meridian.docc/NavigationPatterns.md`.
- **Deep-link-as-data** (pattern): a pure `URL → [Route]` parser; `replaceStack`
  is the deep-link primitive; the async `NebulaRouter` port is the cross-actor
  bridge to the `@MainActor` router. `Codable` `Route` → state restoration.
- Tests: `Meridian/Tests/MeridianTests/DeepLinkTests.swift` — deep-link parse →
  `[Route]` assertions, `replaceStack` via the async port, `Destination`
  `Identifiable` + single-optional "impossible states" assertions. 7 new tests
  (13 total / 3 suites in Meridian), zero warnings.

## [0.2.0] - 2026-07-19

The **Clean Architecture toolkit** — the second surface of Nebula (foundation + architecture). A new
`Sources/Nebula/Architecture/` subtree ships the **seams** that help — and let — an app implement
Clean Architecture efficiently, without Nebula owning any presentation, database, or framework code.
Concrete adapters (repositories, gateways, presenters, URLSession networking) live in the app; Cosmos
is the presentation layer. Presentation patterns (MVVM / MVC / VIP / VIPER) are explicitly out of scope.
The toolkit is pure Swift + Foundation + `Synchronization`; every symbol sits at the Nebula 26 floor
(no above-floor gates). 509 tests / 107 suites green; zero concurrency warnings under Swift 6 mode.
Wave H complete — see `ROADMAP.md`. ADR in `DECISIONS.md`.

### Added
- **Architecture/Domain** — `NebulaValue` / `NebulaEntity` / `NebulaAggregate` markers + `NebulaID<Entity>`
  phantom-typed UUID identity (1-param — generic-parameter defaults are rejected on this toolchain,
  verified `swiftc -parse`; `Codable` intentionally not conformed on the type).
- **Architecture/Ports** — bare `Sendable` markers `NebulaInputPort` / `NebulaOutputPort` / `NebulaDTO`.
  Nebula defines no presenter.
- **Architecture/Errors** — `NebulaFailure: Error, Sendable` protocol + per-layer open structs
  `NebulaDomainError` / `NebulaValidationError` (`Sendable`/`Equatable`/`Hashable` derived) bridging to
  the CLOSED `NebulaError.Kind` enum via a caller-picked `toNebulaError(kind:)` — NO new `Kind` cases.
  `NebulaError.init(error:)` dispatches `NebulaFailure` before the `NSError` fallback.
- **Architecture/UseCase** — `NebulaUseCase<I, O>` generic `Sendable` struct over a `@Sendable`
  `(I) async throws -> O` body (NOT a protocol + `AnyUseCase` box) + `NebulaUseCaseRole` closed
  command/query enum + `NebulaUseCaseBody` typealias; `execute(_:)` (untyped `throws`) and
  `executeTyped(_:) async throws(NebulaError)` (SE-0413, preserves a thrown `NebulaError`, bridges
  others via `NebulaError(error:)`). Decorators `.logged(using:)` / `.measured(using:)` /
  `.reported(using:)` / `.instrumented(using:measure:error:)` route to the EXISTING log/measure/error
  configs (NO 5th config); `.instrumented` composes `reported().measured().logged()`.
- **Architecture/Repository** — PAT `NebulaRepository<Element>: Sendable` + capability sub-protocols
  `NebulaReadOnlyRepository` (`stream()`/`count()`) / `NebulaKeyedRepository` (`find(id:)` requirement,
  `Element: NebulaEntity`) / `NebulaWritableRepository` (`save(_:)`, no `update` verb) /
  `NebulaDeletableRepository` (`delete(_:)`). `stream()` returns concrete `AsyncThrowingStream` (a
  `some AsyncSequence` return is illegal in a protocol requirement). `NebulaRepositoryError`
  (`Source` enum `.local`/`.remote`/`.unknown`; open `Kind` with presets `.notFound`/`.alreadyExists`/
  `.storeFailure`/`.mapping`/`.constraintViolation`/`.cancelled`/`.unknown`; factory statics) conforming
  to `NebulaFailure`.
- **Architecture/Gateway** — `NebulaGateway` marker + `NebulaGatewayConfiguration` (Sendable ONLY — NOT
  `Equatable`, mirrors `NebulaErrorConfiguration`; reuses `NebulaJSONDecoder`/`NebulaJSONEncoder`;
  `.with*` builders + `report(_:)`) + `NebulaGatewayConfig` process-wide `Mutex` accessor.
- **Architecture/Validation** — `NebulaValidator<T>` (sync, `Rule` closures, `validate(_:)`
  short-circuits on the first failing rule, `+` composes) + `NebulaAsyncValidator<T>` (async,
  `AsyncRule` closures may `await`/`throw`; a thrown I/O error propagates out — it is NOT a `.failure`).
- **Architecture/Registry** — `NebulaRegistryKey` (open `Sendable` `ExpressibleByStringLiteral` struct,
  mirrors `NebulaLogCategory`; presets `.repository`/`.gateway`/`.useCase`) +
  `NebulaRegistryConfiguration` (Sendable ONLY, transient `@Sendable () -> Any` factories,
  `.withFactory(for:_:)`) + `NebulaRegistry` (explicit constructor-injection `resolve(_:as:)`) +
  `NebulaRegistryConfig` (process-wide `Mutex` accessor). DI **without** a container.
- **Architecture/Testing** — in-target test doubles `NebulaFakeRepository` (keyed/writable/deletable
  in-memory; `final class` + `let Mutex`, `Sendable` **derived** — final class with all-`let`
  `Sendable` properties, no `@unchecked`) /
  `NebulaStubUseCase` (canned `Result<O, NebulaError>`, `execute` + `executeTyped`) /
  `NebulaSpyUseCase` (records inputs, `callCount`/`inputs()`, delegates to `body`). Ship in the main
  target (decision #8).
- **Architecture/Async** — `NebulaResultPipeline<T: Sendable>` (`map`/`flatMap`/`recover` `@Sendable`
  async transforms over `Result<T, NebulaError>`; `map` bridges thrown errors via `NebulaError(error:)`;
  `.failure` short-circuits) + `AsyncSequence.nebulaChunked(byCount:)` / `nebulaUniqued(on:)` /
  `nebulaUniqued()` (constrained `Self: Sendable, Element: Sendable`, return concrete
  `AsyncThrowingStream`; `nebula*` prefix — no stdlib pollution).
- **DocC** — `Architecture.md` canonical article + 10 per-subsystem articles
  (`ArchitectureDomain`/`Ports`/`Errors`/`UseCase`/`Repository`/`Gateway`/`Validation`/`Registry`/
  `Testing`/`Async`); linked from the module root `Nebula.md`.
- **Governance docs** — `ARCHITECTURE.md` (Architecture section), `DECISIONS.md` (Wave H ADR,
  Accepted), `ROADMAP.md` (Wave H shipped), `VERSIONING.md` (toolkit at-floor row). Vault: 11
  architecture notes marked shipped.

### Deferred (not in 0.2.0; tracked in `ROADMAP.md` → "Later")
- `NebulaInvariant` (decision #6 — validator ergonomics).
- `NebulaMockRepository` (decision #8 — ship Fake/Stub/Spy only in v1).
- `NebulaHTTPGateway` (decision #8-resolved — ship the seam only; the app provides URLSession).
- `NebulaCancellation` / `NebulaError.wrapAsync` (decision #13 — reuse `Task.checkCancellation()` and
  inline do/catch).
- Template multi-module `Domain` product (decision #10 — single-target; document the recommended
  app `Domain` module).

## [0.1.0] - 2026-07-18

First tagged release. The first **complete** Nebula foundation: the four `Sendable` configuration
contracts, the `NebulaError` envelope with lossy mapping, the seven extension groups, `NebulaStandards`,
`NebulaMeasureConfiguration`, the DocC catalog, and the GitHub CI matrix. 379 tests green; zero
concurrency warnings under Swift 6 mode. Waves A–G complete — see `ROADMAP.md`.

### Added
- **Package scaffold** — SPM package `Nebula` for Apple v26 platforms (iOS / macOS / tvOS /
  watchOS / visionOS, all `.v26`); `swift-tools-version: 6.3` (dual Xcode 26.4+ / Xcode 27 build;
  OS-27-only SDK symbols compile-gated `#if swift(>=6.4)` — graceful fallback on Swift 6.3,
  enabled on Swift 6.4); `swiftLanguageModes: [.v6]`; `defaultLocalization: "en"`; single
  `Nebula` target + `NebulaTests` (Swift Testing); no third-party dependencies;
  `.process("Resources")` commented out (foundation emits developer-facing English log/error
  text; no String Catalog by default — the deliberate divergence from Cosmos, which ships
  `.xcstrings` for UI strings).
- **Sources/Nebula folder tree** — `Nebula.swift` (top-level `Nebula` enum + `NebulaVersion`),
  `Logging/`, `Errors/`, `Extensions/{DateTime,String,Number,Primitive,Collection,Codable,DataURL}/`,
  `Standardize/`, `Measure/`, `Nebula.docc/` (internal physical boundaries, not module
  boundaries — one `import Nebula`).
- **NebulaVersion** — `NebulaVersion(major: 26, minor: 0, patch: 0)` in the top-level `Nebula.swift`
  (Nebula N == OS N baseline; the canonical `@available(iOS 26, macOS 26, tvOS 26, watchOS 26,
  visionOS 26, *)` spelling lives in `CLAUDE.md`/`VERSIONING.md`).
- **Logging** — `NebulaLogConfiguration` (level, category, subsystem, min level, `@Sendable`
  handler, fluent `.with*`, `logger()`/`log(_:_:)`) + `NebulaLogConfig` process-wide `Mutex`
  accessor; `NebulaLogger` (Sendable struct over `os.Logger` — exposes `osLogger` for the
  redaction-preserving `OSLogMessage` path and `String` convenience level methods for the simple
  path; `os.Logger` cannot be wrapped, compile-verified); `NebulaLogLevel`, `NebulaLogCategory`,
  `NebulaLogEvent`; `NebulaSignposter`/`NebulaSignpostID`/`NebulaSignpostIntervalState`/
  `NebulaSignpostMetadata` (typealias = `os.SignpostMetadata`); `NebulaMemoryLogHandler` (`final
  class @unchecked Sendable`, `Mutex<T>`-backed ring buffer; test/preview-only).
- **Errors** — `NebulaError` (`Error`/`LocalizedError`/`CustomNSError`/`Sendable`/`Hashable`) +
  nested `Code`/`Kind`/`Context`/`Box` (final class — struct recursion illegal); lossy mapping
  inits from `NSError`/`DecodingError`/`URLError`/`CocoaError`/`any Error` + `EncodingError`;
  `NebulaError.wrap(_:) -> Result<T, NebulaError>`; `NebulaErrorConfiguration` (Sendable ONLY —
  NOT `Equatable`) + `NebulaErrorEvent` (Sendable + Equatable) + fluent `.with*`; `NebulaErrorConfig`
  process-wide `Mutex` accessor; `NebulaDecodingError`/`NebulaEncodingError`.
- **Extensions — DateTime** — `Date` arithmetic/predicates (DST-safe via
  `calendar.dateInterval(of:for:)`); `DateComponents` builders;
  `DateInterval.init(start:duration: Swift.Duration)`; `NebulaDateFormat`/`NebulaDurationFormat`
  façades. ISO/stable presets pinned to `Locale(identifier: "en_US_POSIX")` + `.gmt`.
- **Extensions — String** — `isBlank`/`nilIfEmpty`/`trimmed`/`truncated(to:with:)`/case
  conversions/base64/hex/URL extraction; `NebulaRegex<Output>` (Sendable, conditional `where
  Output: Sendable`); `NebulaRegexPatterns` (curated literals — UUID/IPv4/hex/semver/ISO-timestamp;
  NO email); `NebulaStringDetectedEntity` over `NSDataDetector` (cached in `Mutex<NSDataDetector?>`);
  `NebulaStringLocalization` (Foundation scope only — no SwiftUI/UIKit scopes).
- **Extensions — Number** — `NebulaFormattingOptions` (Sendable + `.with*`); `NebulaNumberFormatting`
  façade (percent/currency/bytes/list/measurement — no legacy Formatter subclasses; `ListFormatter`
  per-call only, never cached); `BinaryInteger`/`BinaryFloatingPoint`/`Decimal` extensions;
  `Decimal.rounded(toDecimalPlaces:)` via `NSDecimalRound` + `NebulaDecimalRoundingRule` enum
  mapping 1:1 to `NSDecimalNumber.RoundingMode`.
- **Extensions — Primitive** — `Comparable.clamped(to:)`; `BinaryInteger.isEven`/`isOdd`/
  `times(_:)`; `Optional.or(_:)`/`orThrow(_:)`/`isNilOrEmpty`; `NebulaNilError` (concrete
  Sendable); `UUID.shortString`/`isValid(_:)`. NEVER redeclares `Bool.toggle()`/`isMultiple(of:)`.
- **Extensions — Collection** — `nebulaChunked`/`nebulaWindows`/`nebulaUniqued`/
  `nebulaStablePartition`/`nebulaPartitioned`/`nebulaSorted`/`nebulaMerging`. `nebula*` prefix on
  open `Collection`/`Sequence` ergonomics (no stdlib pollution); eager by default; non-escaping
  `rethrows`. (`nebulaFiltered(by:)` over `Foundation.Predicate` and `NebulaFrequency` were deferred
  to post-0.1.0 — see ROADMAP.)
- **Extensions — Codable** — `NebulaJSONDecoder`/`NebulaJSONEncoder` (Sendable wrappers holding a
  configure-once-frozen `JSONDecoder`/`JSONEncoder` in a `let`);
  `NebulaJSONDecoderConfiguration`/`NebulaJSONEncoderConfiguration` (Sendable + `.with*`, all
  strategy enums Sendable); `Decodable.init(fromJSON:)`/`Encodable.toJSONData`/`toJSONString`/
  `Data.asPrettyJSONString`. NO `OutputFormatting.fragmentsAllowed` (does not exist).
- **Extensions — Data/URL** — `Data.nebulaHexEncodedString`/`init?(nebulaHexEncoded:)` (Foundation
  has NO native hex); `NebulaHashAlgorithm` (Sendable enum over CryptoKit SHA256/384/512 — the
  ONLY `import CryptoKit`); `Data.nebulaDigest`/`nebulaHexDigest`;
  `URL.nebulaAppending(queryItem:)`/`nebulaSettingQueryItem`/`nebulaRemovingQueryItem`/
  `nebulaPercentEncoded()`; `URLComponents.nebulaWith(queryItem:)` fluent builders.
- **Standardize** — `NebulaStandards` (formatting façade over the modern `FormatStyle` family;
  `.withLocale`/`.withTimeZone`/`.withCalendar`; typed accessors only — no polymorphic
  `.format(_:)`) + `NebulaStandardsConfig` (process-wide `Mutex` accessor). DateComponents
  accessors gated `@available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)`.
- **Measure** — `NebulaMeasureConfiguration` (the 4th config struct — carries
  `measure(_:operation:)`/`bench(_:iterations:warmup:operation:)` ON the config, mirroring
  `NebulaLogConfiguration.log`; NO separate `NebulaMeasure` type) + `NebulaMeasureResult`
  (minimal: name/iterations/total/perIteration — no p50/p99 yet) + `NebulaMeasureConfig`
  (process-wide `Mutex` accessor).
- **Above-floor gates (Nebula 26.4)** — `Data.Base64EncodingOptions.base64URLAlphabet`/
  `.omitPaddingCharacter`, `String.Encoding.ianaName` getter AND `init?(ianaName:)`,
  `UUID.random(using:)`, all gated `@available(iOS 26.4, macOS 26.4, tvOS 26.4, watchOS 26.4,
  visionOS 26.4, *)`.
- **DocC catalog** — `Sources/Nebula/Nebula.docc/` (auto-discovered by SwiftPM because it is
  inside the target's source directory); root article + subsystem articles. Built natively in
  Xcode 26/27; CLI generation via `xcodebuild docbuild` (no `swift-docc-plugin` —
  `Package.swift` keeps `dependencies: []` pristine).
- **GitHub CI** — `.github/workflows/ci.yml` — 5-platform matrix (iOS/macOS/tvOS/watchOS/visionOS)
  + `swift build -c release` to exercise `#if os()` coverage; Xcode 26.4+ pinned.
- **Governance docs** — `CLAUDE.md` (binding guidelines), `ARCHITECTURE.md`, `DECISIONS.md`,
  `VERSIONING.md`, `ROADMAP.md`, `CONTRIBUTING.md`, `PROPOSAL.md`, `README.md`, `CHANGELOG.md`.
- **Obsidian vault MOC** — `vault/Home.md` + 12 verified research notes across `01-fundamentos/`
  (10 foundation subsystems) and `03-padroes/` (2 patterns: `nebula-spm-architecture`,
  `nebula-swift6-concurrency`), each adversarially re-verified against the Xcode 27 Beta 3 SDKs.
  The `.swiftinterface` is the authoritative ground truth; WebFetch-sourced availability tables
  were rejected where they conflicted (UUID.random, percentEncodedQueryItems,
  `OutputFormatting.fragmentsAllowed`, `convertFromKebabCase`, `base64Encode`, a parameterless
  `UUID.random()`, "UUID is not Comparable" — all hallucinated).

### Deferred (not in 0.1.0; tracked in `ROADMAP.md` → "Later")
- `NebulaLogStoreExporter`/`NebulaLogStoreEntry` (macOS-only log-store exporter; `#if os(macOS)`
  + explicit per-platform unavailable).
- `NebulaLocked<Value>`/`NebulaFlag`/`NebulaOnce` (`~Copyable`/`Sendable` concurrency wrappers
  around `Mutex`/`Atomic`).
- `NebulaClock` (ContinuousClock/SuspendingClock wrapper — measure currently uses
  `any Clock<Duration>` directly).
- `NebulaMeasureResult` distribution stats (min/max/mean/p50/p99).
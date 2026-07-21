# Bodies & Downloads (Multipart + Download + Pagination)

Three **additive** surfaces on top of the existing buffered HTTP gateway: a pure `multipart/form-data` body composer, a download façade over `URLSession.download(for:delegate:)`, and a generic pagination helper — with **zero gateway changes**. Pinning is reused from N17a via composition/forwarding.

## Overview

N17c ships three **additive** surfaces that do not touch ``NebulaHTTPGateway`` / ``NebulaHTTPClient`` / ``NebulaHTTPBody`` / ``NebulaHTTPRequest`` / ``NebulaHTTPRequestParser``:

- **Multipart** — ``NebulaMultipartBuilder`` is a pure `multipart/form-data` (RFC 2388) `Data` composer: it assembles ``NebulaMultipartPart``s under a random boundary and writes the body to a temp file for streaming uploads via `URLSession.upload(for:fromFile:)`. Foundation has **no** multipart API (a full grep of `Foundation.swiftinterface` for `multipart` / `form-data` / `boundary` returns zero hits) — this is genuinely new app-layer code, not a wrapper.
- **Download** — ``NebulaDownload/download(for:session:configuration:)`` returns a ``NebulaDownloadHandle`` exposing a `progress: AsyncThrowingStream<Double, any Error>` (fraction 0.0–1.0) + a `value() async throws -> URL` (the moved destination file URL). It wraps `URLSession.download(for:delegate:)` (a temp-file URL deleted on return — the façade moves it via a caller-supplied destination closure), bridges the `URLSessionDownloadDelegate` byte-count callbacks into the progress stream (Foundation has **no** async `for await` progress API), and retries with resume data (`cancel(byProducingResumeData:)` wrapped in `withCheckedContinuation`; `URLError.downloadTaskResumeData` on failure).
- **Pagination** — ``NebulaPagedSequence<Page: Sendable>`` is a generic helper returning `AsyncThrowingStream<Page, any Error>` (the CLAUDE.md-mandated concrete return). `first` / `next` closures decouple cursor transport (the app's concern) from the loop (Nebula's concern).

```swift
// Multipart → gateway-compatible: feeds the existing NebulaHTTPBody.data(_:contentType:).
let form = NebulaMultipartBuilder()
    .adding(.field(name: "title", value: "Nebula"))
    .adding(.file(name: "upload", filename: "f.bin",
                  contentType: "application/octet-stream", data: bytes))
    .build()
let request = NebulaHTTPRequest.post(url, body: .data(form.data, contentType: form.contentType))

// Download → pinning rides the session delegate (the N17a delegate).
let pinned = NebulaDownload.pinned(by: policy)
let handle = NebulaDownload.download(for: request, session: pinned.session)
for try await fraction in handle.progress { … }
let moved = try await handle.value()

// Pagination → app supplies the cursor logic; Nebula drives the loop.
let pages = NebulaPagedSequence(first: fetchFirst, next: fetchNext)
for try await page in pages.stream() { … }
```

## Multipart

``NebulaMultipartBuilder`` is an immutable value type: ``adding(_:)`` returns a new builder (fluent), and ``build()`` produces a ``NebulaMultipartFormData`` with no side effects. The boundary auto-generates via `Data.random(in:)` + ``Data/nebulaHexEncodedString()`` under ``boundaryPrefix`` (`"----NebulaBoundary"` + 16 random bytes hex-encoded → a 50-char boundary, within RFC 2046 §5.1.1's 0–70-char limit). No `import CryptoKit` — multipart doesn't hash.

`build()` is **pure** (no `URLSession`, no `@Sendable` closure, no I/O except the explicit ``file(in:)`` writer). Each part is encoded as `--<boundary>\r\n` + `Content-Disposition: form-data; name="…"` (with `; filename="…"` for file parts) + an optional `Content-Type: <contentType>\r\n` + `\r\n` + body + `\r\n`, then the closing `--<boundary>--\r\n`. ``file(in:)`` writes the built `Data` to a temp file (atomic) and returns its URL for `URLSession.upload(for:fromFile:)` (a file body streams from disk and is suitable for large/background uploads, unlike the in-memory `URLSession.upload(for:from:)`).

**Gateway-compatible by design**: the built `Data` + content-type feed the existing ``NebulaHTTPBody/data(_:contentType:)`` case (a raw body + a content-type) — **no new `NebulaHTTPBody` case**, no ``NebulaHTTPRequest`` / ``NebulaHTTPRequestParser`` ripple. The buffered ``NebulaHTTPGateway`` (Wave N1) carries it unchanged.

## Download

``NebulaDownload/download(for:session:configuration:)`` returns a ``NebulaDownloadHandle``. Internally it creates a ``NebulaDownloadDelegate`` (the per-task delegate), drives the download in an internal `Task`, and returns immediately. The handle exposes:

- `progress: AsyncThrowingStream<Double, any Error>` — fractions 0.0–1.0, bridged from ``NebulaDownloadDelegate``'s `didWriteData` callback. Finishes on completion, failure, or cancellation (the consumer's `for try await` ends **normally** on cancellation — it does not throw `CancellationError`).
- ``value()`` — awaits the moved destination file URL (the temp-file URL `URLSession.download(for:)` returns is moved to the ``NebulaDownloadConfiguration/destination`` before the call returns, so the façade ignores that returned URL — the delegate is the source of truth).
- ``cancelByProducingResumeData()`` — requests resume data from the underlying `URLSessionDownloadTask` (the explicit cancel-with-resume path; the async `download(for:)` overlay does not expose the task — it is captured in the delegate).

### Delegate routing

The `delegate:` passed to `download(for:delegate:)` is a **per-task** delegate that receives the `URLSessionDownloadDelegate` callbacks (`didFinishDownloadingTo` / `didWriteData` / `didCompleteWithError`). SSL/TLS pinning rides the **session** delegate (set at `URLSession(init:)` — the server-trust auth challenge is a session-level `URLSessionDelegate` method). So ``NebulaDownloadDelegate`` holds **no pinning logic** — pinning is the session delegate's concern (the N17a ``NebulaURLSessionDelegate``), wired by ``NebulaDownload/pinned(by:sessionConfiguration:configuration:logger:)``. **Zero N17a source change, zero pinning-logic duplication, no `import Security` in the product target.**

### Resume + retry loop

The retry-with-resume loop is **custom** (NOT ``NebulaRetry/withPolicy``): the resume `Data` mutates the attempt (`download(resumeFrom:)` instead of `download(for:)`), and `withPolicy`'s `operation` is nullary — it cannot carry the resume data between attempts (the SSE `Last-Event-ID` precedent). On a `URLError` carrying `downloadTaskResumeData` (with `configuration.resume` and a retry budget), the loop sleeps (the injectable ``NebulaDownloadConfiguration/sleeper``) and replays `download(resumeFrom:)`. The loop mirrors `withPolicy`'s cancellation contract — cancellation is honored immediately and **never retried**; `value()` throws `CancellationError` on consumer cancellation. `onTermination` on the progress stream cancels the internal loop so the download task is torn down.

There is **no async `cancel(byProducingResumeData:)`** (the completion-handler form is the only one), so ``NebulaDownloadHandle/cancelByProducingResumeData()`` wraps it in a `withCheckedContinuation` (the N17b `sendPing` precedent).

## Pagination

``NebulaPagedSequence<Page: Sendable>`` is a generic `Sendable` struct. `first` fetches the first page; `next(_:)` returns the next page or `nil` to stop (the app extracts the cursor from the page — URL query item, header, or body token — and either fetches the next page or returns `nil`). This decouples cursor transport (the app's concern) from the loop (Nebula's concern). The loop mirrors ``NebulaSSEEventStream``'s build-closure + `Task` + `onTermination → loop.cancel()`: it yields pages until `next` returns `nil`, honors cancellation (the consumer's iteration ends normally on cancel — N17b semantics), and surfaces `first`/`next` errors by finishing the stream throwing. **No retry** — pagination surfaces a failed page's error (retry is the app's concern via ``NebulaRetry/withPolicy`` around the `first`/`next` closures if desired). The custom loop is **not** `withPolicy` (the cursor mutates per page — the SSE `Last-Event-ID` shape).

## Errors

``NebulaMultipartError`` and ``NebulaDownloadError`` are open-struct errors mirroring ``NebulaSSEError`` / ``NebulaWebSocketError``: an extensible ``NebulaMultipartError/Kind`` / ``NebulaDownloadError/Kind`` (a string literal — new categories need no library release) plus the coarse ``NebulaError/Kind`` mapping and the `toNebulaError(kind:)` bridge. **No new ``NebulaError/Kind`` case** is added (the closed envelope stays closed). `coarseKind` maps `.network` for the operational failures (build/io/download/move/resume) and `.unknown` for cancellation/unknown (`default → .unknown`). Domains are `"Nebula.NebulaMultipartError"` / `"Nebula.NebulaDownloadError"`.

## Sendability

All N17c symbols are below the `.v26` floor on every platform (`URLSession.upload(for:fromFile:delegate:)` / `URLSession.download(for:delegate:)` are macOS 12 / iOS 15 / watchOS 8 / tvOS 15 / visionOS 1.0+; `URLError.downloadTaskResumeData` is macOS 10.15 / iOS 13 / watchOS 6 / tvOS 13; `cancel(byProducingResumeData:)` is macOS 10.9 / iOS 7 / watchOS 2 / tvOS 9; `URLComponents` / `URLQueryItem` are far below) — **no `@available` gate** anywhere in N17c. `URLSession` / `URLSessionDownloadTask` / `Progress` / `URLComponents` / `URLQueryItem` are `NS_SWIFT_SENDABLE` (verified against `NSURLSession.h` / `NSProgress.h` / `.swiftinterface`, not assumed). ``NebulaDownloadDelegate`` is a `final class : NSObject, URLSessionDownloadDelegate, Sendable` — `Sendable` is **derived** (all stored props are immutable `let`s of Sendable type, including the `Mutex` box; `URLSessionDownloadDelegate` is an `@objc` protocol NOT annotated `NS_SWIFT_SENDABLE`, but conformance does not block derived `Sendable` on a `final class` with all-`let` Sendable props — the N17b ``NebulaWebSocketSessionDelegate`` analogy). Probed against the Xcode 27 Beta 3 SDK → EXIT=0. **No `@unchecked`** on any value type; all public value types (`NebulaMultipartPart` / `NebulaMultipartFormData` / `NebulaMultipartBuilder` / `NebulaMultipartError` / `NebulaDownloadConfiguration` / `NebulaDownloadHandle` / `NebulaDownloadError` / `NebulaPagedSequence`) derive `Sendable` from value-type fields. `NebulaDownloadConfiguration` / `NebulaDownloadHandle` are `Sendable` but **NOT `Equatable`** (the `@Sendable` closures — mirroring ``NebulaSSEConfiguration``'s not-`Equatable` flavor). `NebulaDownloadConfiguration` is **per-call** (no `Mutex` accessor, unlike the process-wide logging/measurement/error configs); `Nebula.md`'s config list is unchanged.

## Testability note

The pure logic — the multipart builder + temp-file writer + error mapping, the pagination loop + cancellation + error propagation, the download error/resume-data extraction seams, the delegate lifecycle (move-to-destination, progress fractions, task capture), and the race-safe completion box — is unit-tested without a live socket. A `URLProtocol`-backed live round-trip over the async `URLSession.download(for:delegate:)` temp-file path **hangs** — `URLProtocol` does not cleanly bridge the async download overlay's temp-file + `didFinishDownloadingTo` dispatch (the overlay never completes). This mirrors the N17a pragmatic stance: a transport seam that is not injectable from a unit test is documented rather than forced. The live round-trip is a compile-only guarantee (the façade builds on all 5 platforms; the move-to-destination + progress + resume behavior is verified at the delegate/loop seams). Consumer cancellation surfaces via the loop's cancellation handling (it resumes the completion box with `CancellationError` from `Task.checkCancellation()` / the `URLError(.cancelled)` branch), **not** via `withCheckedThrowingContinuation` auto-cancellation, which does not throw on Task cancel without a `withTaskCancellationHandler` bridge.

## Topics

### Multipart
- ``NebulaMultipartBuilder``
- ``NebulaMultipartBuilder/boundaryPrefix``
- ``NebulaMultipartBuilder/init(boundary:parts:)``
- ``NebulaMultipartBuilder/adding(_:)``
- ``NebulaMultipartBuilder/build()``
- ``NebulaMultipartBuilder/file(in:)``
- ``NebulaMultipartPart``
- ``NebulaMultipartPart/field(name:value:)``
- ``NebulaMultipartPart/field(name:value:)-6twkf``
- ``NebulaMultipartPart/file(name:filename:contentType:data:)``
- ``NebulaMultipartFormData``

### Download
- ``NebulaDownload``
- ``NebulaDownload/download(for:session:configuration:)``
- ``NebulaDownload/resume(from:session:configuration:)``
- ``NebulaDownload/pinned(by:sessionConfiguration:configuration:logger:)``
- ``NebulaDownloadHandle``
- ``NebulaDownloadHandle/progress``
- ``NebulaDownloadHandle/value()``
- ``NebulaDownloadHandle/cancelByProducingResumeData()``
- ``NebulaDownloadDelegate``
- ``NebulaDownloadConfiguration``
- ``NebulaDownloadConfiguration/default``
- ``NebulaDownloadConfiguration/withDestination(_:)``
- ``NebulaDownloadConfiguration/withResume(_:)``
- ``NebulaDownloadConfiguration/withMaxResumeAttempts(_:)``
- ``NebulaDownloadConfiguration/withResumeDelay(_:)``
- ``NebulaDownloadConfiguration/withSleeper(_:)``
- ``NebulaDownloadConfiguration/withLogger(_:)``
- ``NebulaDownload/PinnedDownloadSession``

### Pagination
- ``NebulaPagedSequence``
- ``NebulaPagedSequence/init(first:next:)``
- ``NebulaPagedSequence/stream()``

### Errors
- ``NebulaMultipartError``
- ``NebulaMultipartError/Kind``
- ``NebulaMultipartError/coarseKind``
- ``NebulaMultipartError/toNebulaError(kind:)``
- ``NebulaDownloadError``
- ``NebulaDownloadError/Kind``
- ``NebulaDownloadError/coarseKind``
- ``NebulaDownloadError/toNebulaError(kind:)``

<!-- Copyright (c) 2026 Nebula. All rights reserved. -->
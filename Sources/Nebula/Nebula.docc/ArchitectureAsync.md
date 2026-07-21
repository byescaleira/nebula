# Async Flow

An async `Result` pipeline and `AsyncSequence` ergonomics mirroring the Collection `nebula*` helpers.

## Overview

- ``NebulaResultPipeline`` — a `Sendable` struct wrapping `Result<T, NebulaError>` with `@Sendable` async `map`/`flatMap`/`recover` transforms, so a use-case output flows through a chain without ad-hoc do/catch blocks. `map`'s transform may `throw`; a thrown error is bridged via ``NebulaError/init(error:)`` (which preserves an existing ``NebulaError`` and bridges ``NebulaFailure`` layer errors). A `.failure` input short-circuits unchanged. `Sendable` is derived.

- `AsyncSequence.nebulaChunked(byCount:)` / `nebulaUniqued(on:)` / `nebulaUniqued()` — the async analogs of the Collection `nebula*` helpers, constrained to `Self: Sendable, Element: Sendable` and returning the concrete `AsyncThrowingStream` (the iteration runs in a `Task` capturing only `Sendable` state). The `nebula*` prefix avoids stdlib namespace pollution.

- ``NebulaRetryPolicy`` / ``NebulaRetry`` / ``NebulaRetryJitter`` (Wave N1) — a framework-agnostic retry loop for any `async throws` operation. `NebulaRetryPolicy` is a `Sendable` value (NOT `Equatable` — it stores a `@Sendable` `isRetriable` predicate): `maxAttempts` (total, including the first), `baseDelay`, `multiplier`, `maxDelay`, `jitter` (`.none`/`.full`/`.equal`), and the predicate. `NebulaRetry.withPolicy(_:sleeper:operation:)` retries on errors the predicate accepts, honors cancellation (a `CancellationError` is never retried; a cancellation during `sleeper` propagates out), and rethrows the original error on exhaustion or for non-retriable errors. The `sleeper` is injectable for tests. The concrete ``NebulaHTTPGateway`` wraps its `URLSession` call in it.

```swift
let pipeline = NebulaResultPipeline(value: 21)
let doubled = await pipeline.map { $0 * 2 }   // .success(42)

for try await chunk in stream.nebulaChunked(byCount: 2) { /* [1,2], [3,4], [5] */ }

// Retry a flaky call with full-jitter exponential backoff.
let value = try await NebulaRetry.withPolicy(.init(maxAttempts: 4)) {
    try await flaky()
}
```

A cooperative-cancellation helper (`NebulaCancellation`) and `NebulaError.wrapAsync` were deferred — callers reuse `Task.checkCancellation()` and an inline do/catch (NebulaRetry uses the minimal `Task.checkCancellation()` form).

## Topics

### Result pipeline
- ``NebulaResultPipeline``
- ``NebulaResultPipeline/map(_:)``
- ``NebulaResultPipeline/flatMap(_:)``
- ``NebulaResultPipeline/recover(_:)``

### Retry
- ``NebulaRetryPolicy``
- ``NebulaRetry``
- ``NebulaRetryJitter``

### AsyncSequence ergonomics
- ``AsyncSequence/nebulaChunked(byCount:)``
- ``AsyncSequence/nebulaUniqued(on:)``

### Pagination
- ``NebulaPagedSequence`` — a generic `Sendable` pagination helper returning `AsyncThrowingStream<Page, any Error>`. `first` / `next` `@Sendable` closures decouple cursor transport (the app's concern — URL query item, header, or body token) from the loop (Nebula's concern), stopping when `next` returns `nil`. The loop honors cancellation (the consumer's iteration ends normally on cancel) and surfaces `first`/`next` errors; it is a custom loop (the cursor mutates per page, the SSE `Last-Event-ID` shape), **not** ``NebulaRetry/withPolicy`` (which is nullary). See <doc:ArchitectureBodiesDownloads> for the full surface.

<!-- Copyright (c) 2026 Nebula. All rights reserved. -->
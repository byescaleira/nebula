# Async Flow

An async `Result` pipeline and `AsyncSequence` ergonomics mirroring the Collection `nebula*` helpers.

## Overview

- ``NebulaResultPipeline`` — a `Sendable` struct wrapping `Result<T, NebulaError>` with `@Sendable` async `map`/`flatMap`/`recover` transforms, so a use-case output flows through a chain without ad-hoc do/catch blocks. `map`'s transform may `throw`; a thrown error is bridged via ``NebulaError/init(error:)`` (which preserves an existing ``NebulaError`` and bridges ``NebulaFailure`` layer errors). A `.failure` input short-circuits unchanged. `Sendable` is derived.

- `AsyncSequence.nebulaChunked(byCount:)` / `nebulaUniqued(on:)` / `nebulaUniqued()` — the async analogs of the Collection `nebula*` helpers, constrained to `Self: Sendable, Element: Sendable` and returning the concrete `AsyncThrowingStream` (the iteration runs in a `Task` capturing only `Sendable` state). The `nebula*` prefix avoids stdlib namespace pollution.

```swift
let pipeline = NebulaResultPipeline(value: 21)
let doubled = await pipeline.map { $0 * 2 }   // .success(42)

for try await chunk in stream.nebulaChunked(byCount: 2) { /* [1,2], [3,4], [5] */ }
```

A cooperative-cancellation helper (`NebulaCancellation`) and `NebulaError.wrapAsync` were deferred — callers reuse `Task.checkCancellation()` and an inline do/catch.

## Topics

### Result pipeline
- ``NebulaResultPipeline``
- ``NebulaResultPipeline/map(_:)``
- ``NebulaResultPipeline/flatMap(_:)``
- ``NebulaResultPipeline/recover(_:)``

### AsyncSequence ergonomics
- ``AsyncSequence/nebulaChunked(byCount:)``
- ``AsyncSequence/nebulaUniqued(on:)``
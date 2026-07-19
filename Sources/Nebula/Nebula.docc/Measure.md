# Measure

Nebula's measure module is a `Sendable` timing configuration carrying `measure(_:)` and `bench(_:)` directly on the config — mirroring how ``NebulaLogConfiguration`` carries `log(_:_:)`. It is the fourth of Nebula's cross-cutting configuration structs.

## Overview

``NebulaMeasureConfiguration`` is a `Sendable` value (NOT `Equatable` — it stores a `@Sendable` closure, mirroring ``NebulaLogConfiguration`` and ``NebulaErrorConfiguration``) describing how work is timed and routed:

- ``NebulaMeasureConfiguration/clock`` — the timing source, `any Clock<Duration>`. Defaults to `ContinuousClock()` (the wall-clock clock WWDC22 recommends for human-relative durations; it advances during system sleep). Pass `SuspendingClock()` for machine-relative timing that pauses with the process.
- ``NebulaMeasureConfiguration/signposter`` — an optional ``NebulaSignposter`` that wraps each `measure` run in an Instruments signpost interval. `nil` by default — a foundation does not force Instruments overhead on consumers; opt in via ``NebulaMeasureConfiguration/withSignposter(_:)`` or by sharing a logger's signposter.
- ``NebulaMeasureConfiguration/isEnabled`` — gates **both** the secondary ``NebulaMeasureConfiguration/handler`` fan-out **and** signpost emission. Timing itself always runs regardless (a measurement that did not measure is worthless), so the returned `Duration` is preserved even when the handler is disabled.
- ``NebulaMeasureConfiguration/handler`` — invoked with a ``NebulaMeasureResult`` on every `bench()` run (not on `measure(_:)`, which returns the `Duration` directly). The default `{ _ in }` is capture-free and trivially `Sendable`.

### `measure(_:)` — sync and async

``NebulaMeasureConfiguration/measure(_:operation:)`` times `operation` once under ``clock`` and, if a ``signposter`` is configured and ``isEnabled``, wraps it in a signpost interval via `OSSignposter.withIntervalSignpost(name)`. It returns `(T, Duration)`.

A key implementation detail: the stdlib `Clock.measure` returns **only** a `Duration` (there is no `(T, Duration)` tuple overload), so the Nebula measure captures the operation's result inside the closure body (`var result: T!`) and returns `(result, elapsed)`.

The async overload of ``NebulaMeasureConfiguration/measure(_:operation:)`` (the `() async throws -> T` form) uses manual `beginInterval`/`endInterval` bracketing because `OSSignposter.withIntervalSignpost` has **no async variant**. `defer` ensures the interval ends even on throw.

### `bench(_:)` — quick micro-benchmark

``NebulaMeasureConfiguration/bench(_:iterations:warmup:operation:)`` runs `warmup` untimed invocations followed by `iterations` timed invocations under ``clock`` and returns a ``NebulaMeasureResult``. It invokes ``handler`` with the result if ``isEnabled``. This is not statistically rigorous — no p50/p99, no clock-resolution check; it runs on the caller's thread. Use it for quick relative comparisons, not publication-grade numbers.

### Result

``NebulaMeasureResult`` is a `Sendable`, `Equatable` snapshot of one `bench()` run: the signpost label (``name``), the iteration count (``iterations``), and the total elapsed ``Duration``. ``NebulaMeasureResult/perIteration`` is `total / iterations` (using `Duration`'s `/ (Duration, Int) -> Duration` overload, which preserves the full seconds + attoseconds precision). ``NebulaMeasureResult/components`` forwards to `Duration.components`.

### Process-wide access

``NebulaMeasureConfig`` holds the current configuration in a `Mutex<NebulaMeasureConfiguration>` (`Synchronization`; below the `.v26` floor). `NebulaMeasureConfig.get()`/`set(_:)` read and replace it.

```swift
let measure = NebulaMeasureConfiguration.default
    .withSignposter(NebulaSignposter(subsystem: "com.acme.app"))

// Single timed run — returns (result, duration).
let (sum, elapsed) = measure("compute") { (0..<1000).reduce(0, +) }

// Micro-benchmark — warmup 2, then 50 timed iterations.
let result = measure.bench("hash", iterations: 50, warmup: 2) {
    _ = payload.withUnsafeBytes { SHA256.hash(data: $0) }
}
print(result.perIteration)   // mean Duration per iteration
```

## Topics

### Configuration
- ``NebulaMeasureConfiguration``
- ``NebulaMeasureConfig``
- ``NebulaMeasureResult``

### Builders
- ``NebulaMeasureConfiguration/withClock(_:)``
- ``NebulaMeasureConfiguration/withSignposter(_:)``
- ``NebulaMeasureConfiguration/withEnabled(_:)``
- ``NebulaMeasureConfiguration/withHandler(_:)``

### Measurement
- ``NebulaMeasureConfiguration/measure(_:operation:)``
- ``NebulaMeasureConfiguration/bench(_:iterations:warmup:operation:)``

### Result accessors
- ``NebulaMeasureResult/perIteration``
- ``NebulaMeasureResult/components``
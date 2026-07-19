# Logging

Nebula's logging module is a `Sendable` facade over `os.Logger` and `os.OSSignposter`, scoped by subsystem and category and routed through one of four cross-cutting configuration structs.

## Overview

Nebula does not reinvent `os.Logger` — it could not even if it wanted to. `os.Logger`'s level methods are annotated `@_semantics("oslog.requires_constant_arguments")`, and `log(level:_:)` carries `oslog.log_with_level`. Both reject a forwarded `OSLogMessage` parameter with "argument must be a string interpolation." The privacy-redacting `OSLogMessage` literal **must** appear directly at an `os.Logger` call site. The same restriction applies to `os.OSSignposter`: its `emitEvent`/`beginInterval`/`endInterval`/`withIntervalSignpost` methods are `constant_evaluable`, so the `name` (`StaticString`) and message (`SignpostMetadata = OSLogMessage`) must be literals at the call site.

Nebula therefore offers **two emission paths**:

- **Primary (redaction-preserving).** ``NebulaLogger`` exposes the underlying `os.Logger` via ``NebulaLogger/osLogger``. Call it directly with an `OSLogMessage` literal so per-argument `.public`/`.private`/`.sensitive`/`.auto` and `.private(mask: .hash)` redaction are honored in Console.app (WWDC20 10168). Use this whenever redaction matters.
- **Secondary (String convenience).** ``NebulaLogger`` and ``NebulaLogConfiguration`` provide `String`-typed level methods (`debug`/`info`/`notice`/`warning`/`error`/`fault`). Each builds a literal at the `os.Logger` call site (so it compiles) but the message is already interpolated to `.public` — **per-argument redaction is not available on this path.** It exists so dynamic strings and handler fan-out can capture events as plain ``NebulaLogEvent`` values.

```swift
let logger = NebulaLogger(subsystem: "com.acme.app", category: .networking)

// Primary path: redaction-sensitive literal at the os.Logger call site.
logger.osLogger.error("Failed \(url, privacy: .public) token=\(token, privacy: .private)")

// Secondary path: dynamic String, defaults to .public — no per-arg redaction.
logger.error("retry attempt \(attempt)")
```

### Configuration, not environment

Nebula has no SwiftUI, so there is no `@Entry`/`@Observable`/`@Environment`. Logging behavior flows through ``NebulaLogConfiguration`` — a `Sendable` value (NOT `Equatable`, because it stores a `@Sendable` closure) carrying `isEnabled`, `subsystem`, `category`, `minLevel`, and a `handler` invoked with a ``NebulaLogEvent`` on every secondary-path emission. Override pieces with fluent `.with*` builders (``NebulaLogConfiguration/withSubsystem(_:)``, ``NebulaLogConfiguration/withCategory(_:)``, ``NebulaLogConfiguration/withMinLevel(_:)``, ``NebulaLogConfiguration/withHandler(_:)``, ``NebulaLogConfiguration/withEnabled(_:)``). ``NebulaLogConfiguration/logger()`` builds a ``NebulaLogger`` for the configured subsystem/category; ``NebulaLogConfiguration/log(_:_:)`` is the secondary `String` convenience path.

For process-wide ergonomics alongside explicit-parameter DI, ``NebulaLogConfig`` holds the current configuration in a `Mutex<NebulaLogConfiguration>` (`Synchronization`; below the `.v26` floor, no gating). `NebulaLogConfig.get()`/`set(_:)` read and replace it; `NebulaLogConfig.log(_:_:)` emits via the current configuration.

### Levels and categories

``NebulaLogLevel`` is the five-level taxonomy mapped 1:1 to `os.OSLogType`: `debug`/`info`/`notice`/`error`/`fault`. `notice` maps to `OSLogType.default` (the os overlay has no `.notice`), and ``NebulaLogLevel/warning`` is a severity alias for `error`, exactly mirroring `Logger.warning`. Levels are `Comparable` by severity so a configuration can gate with `level >= minLevel`.

``NebulaLogCategory`` is a `Sendable`, `ExpressibleByStringLiteral` struct (not a closed enum) — `os.Logger` accepts a plain `String` category, so consumers can invent categories (`"background-sync"`) without a library release. Presets include ``NebulaLogCategory/networking``, ``NebulaLogCategory/persistence``, ``NebulaLogCategory/formatting``, ``NebulaLogCategory/measure``, ``NebulaLogCategory/concurrency``, and ``NebulaLogCategory/general``.

### Signposts

``NebulaSignposter`` is the `Sendable` facade over `os.OSSignposter`. Like the logger, it cannot wrap the underlying type — ``NebulaSignposter/osSignposter`` is the escape hatch for `emitEvent`/`beginInterval`/`endInterval`/`withIntervalSignpost` with literal names. Nebula-typed ``NebulaSignposter/makeSignpostID()`` and ``NebulaSignposter/makeSignpostID(from:)`` return ``NebulaSignpostID`` (a `Sendable` wrapper around `os.OSSignpostID`), and `beginInterval` hands back an `os.OSSignpostIntervalState` wrapped as ``NebulaSignpostIntervalState``. ``NebulaSignpostMetadata`` is a `Sendable` alias for `os.SignpostMetadata`. A logger's signposter is available via ``NebulaLogger/signposter``; the measure module reuses it (see <doc:Measure>).

```swift
let s = NebulaSignposter(subsystem: "com.acme.app")
let id = s.makeSignpostID()
let state = s.osSignposter.beginInterval("load", id: id.rawValue)
// ... work ...
s.osSignposter.endInterval("load", state)
```

### In-memory sink (tests and previews)

``NebulaMemoryLogHandler`` is a `final class @unchecked Sendable` backed by a `Mutex<[NebulaLogEvent]>` ring buffer — the only `@unchecked` type in the logging module, justified by the lock and safe because it is a reference type, not a Nebula-defined value type. It is intended for tests and previews; plug its ``NebulaMemoryLogHandler/handler`` into a ``NebulaLogConfiguration/withHandler(_:)`` to capture events, then read them with ``NebulaMemoryLogHandler/snapshot()``.

## Topics

### Logger
- ``NebulaLogger``
- ``NebulaLogCategory``
- ``NebulaLogLevel``

### Configuration
- ``NebulaLogConfiguration``
- ``NebulaLogConfig``
- ``NebulaLogEvent``
- ``NebulaMemoryLogHandler``

### Signposts
- ``NebulaSignposter``
- ``NebulaSignpostID``
- ``NebulaSignpostIntervalState``
- ``NebulaSignpostMetadata``
# Errors

Nebula's error module is a uniform, `Sendable`, throwable error envelope with deterministic `NSError` bridging, plus a configuration/handler contract that mirrors the logging module.

## Overview

``NebulaError`` is the standard error shape for the foundation. It conforms to `Error`, `LocalizedError`, and `CustomNSError` for deterministic `NSError` bridging; it is `Sendable` (derived — no `@unchecked`) and `Hashable`, so it crosses actor boundaries and rides inside `@Sendable` handlers. It carries structured metadata — a `(domain, code)` identifier, a coarse `Kind`, a human-facing message, failure reason, recovery suggestions, help anchor, free-form string metadata, decoding/validation context, a date, and one nested underlying error.

### Lossy-but-Sendable mapping

`any Error` is not `Sendable` (SE-0302). To keep the envelope `Sendable`, the lossy mapping initializers in ``NebulaError`` **consume** the source error at construction time and keep only `Sendable` fragments. Consumers needing the original error must catch it before mapping.

- ``NebulaError/init(_:)`` maps an `NSError`: the domain/code become ``NebulaError/Code``; `NSLocalized*` userInfo entries populate the localized fields; remaining `String`-valued userInfo populates `metadata`; `kind` is inferred from the domain; `NSUnderlyingErrorKey` is wrapped as a single-level ``NebulaError/underlying`` (deep chains flatten to one level).
- ``NebulaError/init(decodingError:)`` maps a `DecodingError` (`kind = .decoding`); the coding path is stringified (`CodingKey` is not `Sendable`-portable) and stored in ``NebulaError/Context``.
- ``NebulaError/init(urlError:)`` maps a `URLError` (`kind = .network`); ``NebulaError/init(cocoaError:)`` maps a `CocoaError` (`kind = .cocoa`).
- ``NebulaError/init(error:)`` dispatches on the concrete type — `NebulaError` (preserved as-is), `DecodingError`, `EncodingError`, `URLError`, `CocoaError`, then `NSError` as the fallback.

> `EncodingError` bridges to `NSError` with domain `NSCocoaErrorDomain` when thrown out of `JSONEncoder`, so the NSError path would misclassify it as `.cocoa`. The `any Error` dispatcher therefore routes `EncodingError` through ``NebulaError/encoding(_:)`` (faithful `kind = .encoding`) instead. Symmetrically, ``NebulaError/decoding(_:)`` mirrors the decoding init.

``NebulaError/wrap(_:)`` runs a throwing closure and captures any thrown error as a `Result<T, NebulaError>` — a thrown `NebulaError` is preserved as-is; any other `Error` is mapped lossily via ``NebulaError/init(error:)``. Per SE-0413, public Nebula APIs use untyped `throws`; `NebulaError` is exposed as an opt-in concrete `Failure` so consumers MAY declare `throws(NebulaError)` / `Result<T, NebulaError>`.

### Nested types

- ``NebulaError/Code`` — a `(domain, code)` pair identifying the error.
- ``NebulaError/Kind`` — a closed `enum` classification: `network`, `decoding`, `encoding`, `cocoa`, `file`, `validation`, `serialization`, `unknown`.
- ``NebulaError/Context`` — decoding/validation context with the coding path stringified, plus debug description and a caller-site tag.
- ``NebulaError/Box`` — a `final class` that breaks the value-type recursion. A Swift `struct` cannot contain itself, so the single nested ``NebulaError/underlying`` must be boxed. `Box` has a `Sendable` `let` value, so its `Sendable` conformance is derived — no `@unchecked`.

### CustomNSError bridging

``NebulaError/errorDomain`` is the stable `"Nebula.NebulaError"`; ``NebulaError/errorCode`` is the code within the domain; ``NebulaError/errorUserInfo`` populates the `NSLocalized*`/`NSUnderlyingErrorKey` constants plus Nebula metadata under `Nebula.<key>` and the kind under `NebulaKind`.

### Reporting contract

``NebulaErrorConfiguration`` is `Sendable` ONLY (NOT `Equatable` — it stores a `@Sendable` closure, which is not `Equatable`, mirroring ``NebulaLogConfiguration``). It carries `isEnabled`, `category`, and a `handler` invoked with a ``NebulaErrorEvent`` on every reported error. ``NebulaErrorConfiguration/report(_:)`` gates on `isEnabled`. Override pieces with fluent `.with*` builders (``NebulaErrorConfiguration/withEnabled(_:)``, ``NebulaErrorConfiguration/withCategory(_:)``, ``NebulaErrorConfiguration/withHandler(_:)``).

``NebulaErrorEvent`` is the `Sendable` **and** `Equatable` snapshot carried into the handler — unlike an `any Error`, its ``NebulaErrorEvent/error`` is a `Sendable` ``NebulaError``, so it crosses actor boundaries.

For process-wide ergonomics, ``NebulaErrorConfig`` holds the current configuration in a `Mutex<NebulaErrorConfiguration>` (`Synchronization`; below the `.v26` floor). `NebulaErrorConfig.get()`/`set(_:)` read and replace it; `NebulaErrorConfig.report(_:)` reports through the current configuration.

### Codable bridges

The Codable extensions module provides ``NebulaDecodingError`` and ``NebulaEncodingError`` — `Sendable, Error` structs that project `DecodingError`/`EncodingError` via a `.nebula` accessor, complementing the lossy mappings on ``NebulaError``. See <doc:Extensions>.

```swift
let cfg = NebulaErrorConfiguration.default
    .withCategory("sync")
    .withHandler { event in NebulaLogConfig.log(.error, event.error.message) }

let result = NebulaError.wrap { try decode(payload) }
switch result {
case .failure(let error): cfg.report(error)   // → handler with a Sendable NebulaErrorEvent
case .success(let value): // ...
}
```

## Topics

### Error envelope
- ``NebulaError``
- ``NebulaError/Code``
- ``NebulaError/Kind``
- ``NebulaError/Context``
- ``NebulaError/Box``

### Mapping and wrapping
- ``NebulaError/init(_:)``
- ``NebulaError/init(decodingError:)``
- ``NebulaError/init(urlError:)``
- ``NebulaError/init(cocoaError:)``
- ``NebulaError/init(error:)``
- ``NebulaError/wrap(_:)``
- ``NebulaError/decoding(_:)``
- ``NebulaError/encoding(_:)``

### Configuration
- ``NebulaErrorConfiguration``
- ``NebulaErrorEvent``
- ``NebulaErrorConfig``

### Codable bridges
- ``NebulaDecodingError``
- ``NebulaEncodingError``
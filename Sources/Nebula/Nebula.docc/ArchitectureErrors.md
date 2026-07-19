# Layer Errors

The architecture-toolkit error dimension: per-layer open structs conforming to ``NebulaFailure``, bridging to the closed ``NebulaError/Kind`` enum.

## Overview

Nebula never adds cases to the closed ``NebulaError/Kind`` enum. Instead, each layer owns an **open struct** (extensible by a `String` `code` without a library release) conforming to ``NebulaFailure``. A layer error carries a `coarseKind` mapping into `NebulaError.Kind` and a ``NebulaFailure/toNebulaError(kind:)`` bridge that the caller invokes with the chosen coarse kind — the caller picks the bridge kind, the layer does not bake it in.

- ``NebulaFailure`` — the `Error, Sendable` protocol every layer error conforms to. Default `coarseKind` is ``NebulaError/Kind/unknown``.
- ``NebulaDomainError`` — a domain-layer error (`coarseKind = .validation` by default).
- ``NebulaValidationError`` — a parse-don't-validate failure produced by ``NebulaValidator`` rules; carries an optional `field` anchor.

All three derive `Sendable`, `Equatable`, and `Hashable` from their fields, so a test can assert a specific layer error with `#expect(throws:)`. The bridge is dispatched from ``NebulaError/init(error:)``: a thrown ``NebulaFailure`` is mapped via `toNebulaError(kind: coarseKind)` before the `NSError` fallback, so ``NebulaUseCase/executeTyped(_:)`` and ``NebulaResultPipeline`` bridge layer errors faithfully.

```swift
struct InsufficientFunds: NebulaFailure { /* … */ }
let nebulaError = error.toNebulaError(kind: .validation)
```

See <doc:Errors> for the foundation envelope, and <doc:ArchitectureRepository> for ``NebulaRepositoryError``.

## Topics

### Protocol
- ``NebulaFailure``
- ``NebulaFailure/coarseKind``
- ``NebulaFailure/toNebulaError(kind:)``

### Layer errors
- ``NebulaDomainError``
- ``NebulaValidationError``
# Validation

Parse-don't-validate: a synchronous validator and an asynchronous validator over a list of rules.

## Overview

- ``NebulaValidator`` — a pure, synchronous `Sendable` struct over ``NebulaValidator/Rule``s. Each rule is a `@Sendable (T) -> NebulaValidationError?` (`nil` passes). ``NebulaValidator/validate(_:)`` short-circuits on the **first** failing rule, returning `Result<T, NebulaValidationError>`. `+` composes validators. `Sendable` is derived (the `@Sendable` rule closures). v1 is minimal — error-accumulating (collect-all-failures) ergonomics are deferred.

- ``NebulaAsyncValidator`` — the async analog over ``NebulaAsyncValidator/AsyncRule``s whose checks may `await` (e.g. a uniqueness check against a ``NebulaKeyedRepository``) and `throw`. A **thrown** error is an I/O failure distinct from a validation failure — it propagates out of ``NebulaAsyncValidator/validate(_:)``, it is **not** a `.failure`. Use the sync ``NebulaValidator`` for pure rules so they do not pay an `async` hop.

```swift
let ageRule = NebulaValidator<Int>.Rule { $0 < 0 ? NebulaValidationError(code: "negative", message: "bad", field: "age") : nil }
let validator = NebulaValidator(ageRule)
if case .failure(let err) = validator.validate(-1) { /* … */ }
```

## Topics

### Synchronous
- ``NebulaValidator``
- ``NebulaValidator/Rule``
- ``NebulaValidator/validate(_:)``

### Asynchronous
- ``NebulaAsyncValidator``
- ``NebulaAsyncValidator/AsyncRule``
- ``NebulaAsyncValidator/validate(_:)``
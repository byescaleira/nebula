# Use Cases

A fine-grained, generic use-case type over a `@Sendable` async body, with CQRS role tagging and a decorator seam routing to the existing log/measure/error configs.

## Overview

``NebulaUseCase`` is a `Sendable` struct generic over `<I: Sendable, O: Sendable>`, wrapping a ``NebulaUseCaseBody`` (`@Sendable (I) async throws -> O`). It is **not** a protocol + type-erased box — the concrete struct is the seam, so there is no `AnyUseCase` allocation and the body is statically dispatched. A ``NebulaUseCaseRole`` (closed `command`/`query` enum) tags the use case for CQRS. The `name: StaticString` is required for signposting.

- ``NebulaUseCase/execute(_:)`` — the untyped-`throws` path (the public API evolution-safe default).
- ``NebulaUseCase/executeTyped(_:)`` — the typed-`throws(NebulaError)` path (SE-0413). A thrown ``NebulaError`` is preserved; any other `Error` (including a ``NebulaFailure`` layer error) is bridged via ``NebulaError/init(error:)``.

### Decorators

Cross-cutting concerns are **decorators** that compose into a new ``NebulaUseCase`` — no fifth configuration struct. They route to the **existing** log/measure/error configs (decision #7).

- ``NebulaUseCase/logged(using:)`` — logs entry/exit/failure via a ``NebulaLogger`` (default ``NebulaLogConfig``).
- ``NebulaUseCase/measured(using:)`` — signposts the execution via ``NebulaMeasureConfiguration``.
- ``NebulaUseCase/reported(using:)`` — reports failures via ``NebulaErrorConfiguration``.
- ``NebulaUseCase/instrumented(using:measure:error:)`` — composes `reported().measured().logged()` in the canonical order; nil arguments fall back to defaults.

```swift
let uc = NebulaUseCase<WithdrawInput, Account>(name: "withdraw", role: .command) { input in
    try await repo.save(input.account.withdrawing(input.amount))
}
.instrumented()   // logged + measured + reported, process-wide defaults
let result = try await uc.executeTyped(input)
```

## Topics

### Use case
- ``NebulaUseCase``
- ``NebulaUseCaseRole``
- ``NebulaUseCaseBody``
- ``NebulaUseCase/execute(_:)``
- ``NebulaUseCase/executeTyped(_:)``

### Decorators
- ``NebulaUseCase/logged(using:)``
- ``NebulaUseCase/measured(using:)``
- ``NebulaUseCase/reported(using:)``
- ``NebulaUseCase/instrumented(using:measure:error:)``
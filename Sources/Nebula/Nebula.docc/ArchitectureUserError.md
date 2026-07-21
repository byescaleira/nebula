# User error bridge

The architecture-toolkit user-facing error surface: a Foundation-tier value (``NebulaUserError``) the presentation layer renders, produced by a configuration-layer map from the closed ``NebulaError`` envelope — mapping only, no new ``NebulaError/Kind`` cases.

## Overview

Apple's error model is two-layer: a *developer-facing* `Error` bridged to `NSError`, and a *user-facing* surface via `LocalizedError` (four optional strings) and `RecoverableError` (an option list plus `attemptRecovery` callbacks). **There is no Apple "user-error value type"** — `LocalizedError` is the port, and *presentation* (the alert, the sheet, the button copy) is UI-tier: AppKit `presentError`, UIKit `UIAlertController`, a SwiftUI alert. Nebula is Foundation-only and defines no presenter — the presentation layer is the **Cosmos** sibling.

``NebulaError`` already conforms to `LocalizedError` and `CustomNSError`, and its `errorUserInfo` carries the developer-facing English `message`, `failureReason`, `recoverySuggestions`, and `helpAnchor`. But ``NebulaError/message`` is developer-facing English — it is not the value an app renders to a user. N12 fills that gap with a **value-mapping bridge** at the configuration layer: `NebulaError → NebulaUserError?`.

### The value, not a layer error

``NebulaUserError`` is a `Sendable`, `Equatable`, `Hashable` struct: a `message`, a list of ``RecoveryAction``s, and an optional `helpAnchor` (aligned with `LocalizedError.helpAnchor`). It is **not** a ``NebulaFailure`` — it is the *opposite* direction. ``NebulaFailure`` bridges a layer error *into* the closed ``NebulaError/Kind`` envelope (``NebulaFailure/toNebulaError(kind:)``); ``NebulaUserError`` is the *output* of a map *out of* that envelope. So it has no `coarseKind`, no `toNebulaError`, and **no** coupling to the closed `Kind` enum — adding user-facing errors never adds a `Kind` case.

### RecoveryAction is Nebula-authored

Apple's `RecoverableError` is **closure-based**: its `attemptRecovery(optionIndex:)` callbacks bake UI and timing into the error value. There is no `RecoveryAction` enum in Apple, so Nebula authors one — a value enum (``RecoveryAction/retry``, ``RecoveryAction/cancel``, ``RecoveryAction/dismiss``, ``RecoveryAction/custom(_:)``) that carries the recoverable intent as **data**, leaving the presentation layer free to surface it. ``NebulaError`` adopting `RecoverableError` is deliberately **deferred** — it would push UI/timing into the error value; an opt-in conformance is an app/Cosmos decision. `RecoveryURL` is not public Apple API (only a private PassKit symbol) and is not modeled.

### The configuration-layer map

``NebulaErrorConfiguration/withUserMessageMap(_:)`` installs a `@Sendable` map keyed by `(NebulaError.Kind, [String: String])` returning an optional ``NebulaUserError``. The dictionary is ``NebulaError/metadata`` — runtime context an app can interpolate into a message. The map returns `NebulaUserError?` so a custom map can decline to surface a kind by returning `nil`. The default map is `{ _, _ in nil }` (opt-in — no user-facing value unless configured).

```swift
// Wire the shipped English fallback:
let config = NebulaErrorConfiguration.default
    .withUserMessageMap { kind, context in
        NebulaUserError.default(for: kind, context: context)
    }

// Resolve a user-facing value for a reported error:
if let user = config.userError(for: error) {
    // app/Cosmos renders user.message + user.recoveryActions
}
```

``NebulaUserError/default(for:context:)`` ships an English fallback per `Kind` with HIG-neutral tone (non-accusatory, no "you/your/we") and sensible recovery actions. The app overrides the map for **localization** via `String(localized:)` at the app layer — Nebula emits developer-facing English only (no `String(localized:)` / `NSLocalizedString` in `Sources/`).

### Orthogonal to reporting

``NebulaErrorConfiguration/userError(for:)`` is **not** gated on ``NebulaErrorConfiguration/isEnabled`` — user-message mapping is orthogonal to reporting. An app can surface a user-facing value whether or not errors are reported. The process-wide convenience is ``NebulaErrorConfig/userError(for:)`` (mirroring ``NebulaErrorConfig/report(_:)``); the explicit-parameter path passes a ``NebulaErrorConfiguration`` directly (the testable path — never resolve from the accessor in a test).

See <doc:ArchitectureErrors> for the layer-error taxonomy (the *input* side of the envelope) and <doc:Errors> for the foundation envelope.

## Topics

### Value
- ``NebulaUserError``
- ``RecoveryAction``
- ``NebulaUserError/default(for:context:)``

### Configuration
- ``NebulaErrorConfiguration``
- ``NebulaErrorConfiguration/withUserMessageMap(_:)``
- ``NebulaErrorConfiguration/userError(for:)``
- ``NebulaErrorConfig/userError(for:)``
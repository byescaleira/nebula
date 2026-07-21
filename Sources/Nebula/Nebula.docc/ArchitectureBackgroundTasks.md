# Background tasks

A `Sendable` scheduling port over `BGTaskScheduler`, a macOS/watchOS-unavailable `final class` façade that conforms to the port, a Sendable launch-time **handle** that drives task completion/expiration, and a `@Sendable` launch handler held in a `Mutex`-backed configuration.

## Overview

`BGTaskScheduler` is `API_UNAVAILABLE(macos) API_UNAVAILABLE(watchos)` — background tasks are an **iOS / tvOS / visionOS** surface. The scheduling surface (register an identifier, submit a request, cancel, enumerate pending) is the port; the system-initiated launch is bridged to the config's single `@Sendable` launch handler through a Sendable handle.

- ``NebulaBackgroundTaskScheduler`` — the **port**, a `Sendable` protocol with five requirements (``NebulaBackgroundTaskScheduler/register(_:)``, ``NebulaBackgroundTaskScheduler/submit(_:)``, ``NebulaBackgroundTaskScheduler/cancel(_:)``, ``NebulaBackgroundTaskScheduler/cancelAll()``, ``NebulaBackgroundTaskScheduler/pendingRequests()``). The launch handler is **not** on the port — it lives on the config.
- ``NebulaBGTaskScheduler`` — the concrete **façade**, a `final class` (no `NSObject` base — there is no `@objc` protocol to back, unlike ``NebulaUNNotificationCenter``) that conforms to the port. It registers each identifier with `BGTaskScheduler.shared`, bridges the system's launch callback to a Sendable ``NebulaBackgroundTask`` handle, and forwards the handle to the config's launch handler.
- ``NebulaBackgroundTask`` — the **Sendable launch-time handle** the launch handler receives. It holds the identifier + kind + two `@Sendable` closures (``NebulaBackgroundTask/complete(success:)`` / ``NebulaBackgroundTask/onExpiration(_:)``) that reach the underlying `BGTask` **through the façade**, not by holding it.
- ``NebulaBackgroundTaskRequest`` / ``NebulaBackgroundTaskKind`` — the value types (all-5; no `BGTask` referenced).
- ``NebulaBackgroundTaskConfiguration`` — the `@Sendable`-handler config (``NebulaBackgroundTaskConfiguration/launch``), held in a `Mutex`; process-wide access via ``NebulaBackgroundTaskConfig``.
- ``NebulaBackgroundTaskError`` — the open-struct background-task-layer error.

```swift
let scheduler = NebulaBGTaskScheduler(
    .default.withLaunch { task in
        Task { /* perform the background work */ task.complete(success: true) }
    }
)
let registered = await scheduler.register("com.example.refresh")
try await scheduler.submit(
    NebulaBackgroundTaskRequest(
        identifier: "com.example.refresh",
        kind: .appRefresh,
        earliestBeginDate: .now.addingTimeInterval(15 * 60)
    )
)
```

> The app must `register(_:)` every identifier **before** the system launches the app to perform it (the registration is typically done at app-launch time, in the composition root). Submitting a request schedules the next system-initiated run; the registered launch handler is invoked when the system later launches the app.

### Why mac/watch-unavailable, not `#if canImport`

`BackgroundTasks.framework` is **physically present on all five SDKs** (headers + `.tbd` on macOS/watchOS too), so `#if canImport(BackgroundTasks)` is `true` on macOS/watchOS — it gates nothing, and the subsequent `BGTaskScheduler.shared` reference then fails because the symbols are `API_UNAVAILABLE(macos) API_UNAVAILABLE(watchos)`. The compile-safe gate is therefore a **type-level `@available(macOS, unavailable) @available(watchOS, unavailable)` declaration** on the Nebula façade (the ``NebulaLogStoreExporter`` precedent): declaring a **Nebula** symbol unavailable suppresses body type-checking on macOS/watchOS, so the unavailable `BGTaskScheduler.shared` reference inside isn't validated there. The type still **exists** on all five platforms (it can be named in shared signatures) — it is merely unavailable on macOS/watchOS.

`@available(macOS 26, unavailable)` is a **syntax error** — `unavailable` takes no version. The valid form is `@available(macOS, unavailable)` (no version). This is the **declaration-gate** form, distinct from the `#if !os(<platform>)` compile gate (used in <doc:ArchitectureNotifications> for an SDK symbol that can't take a declaration gate) and from the `#if canImport(<framework>)` whole-file gate (reserved for a genuinely **absent** framework).

### The non-`Sendable` `BGTask` and the `@unchecked` reference-type box

`BGTask` is non-`Sendable` and system-delivered **inside** the `@Sendable` launch callback. Storing it directly behind a `Mutex<[String: BGTask]>` fails whole-module Swift 6 with a **region-isolation wall** (`'inout sending' parameter '$0' cannot be task-isolated`): a non-Sendable class arriving as a closure parameter can't be `sending`-transferred into a `Mutex` region the compiler can't prove is exclusive. The ``NebulaDefaults`` `Mutex<non-Sendable>` precedent does **not** apply — `UserDefaults.standard` arrives at a public `sending` API the caller asserts; `BGTask` arrives in a launch closure where exclusivity is unprovable.

The resolution is a minimal `final class @unchecked Sendable` ``NebulaBGTaskBox`` reference-type wrapper holding the `BGTask` as an **immutable `let`** (no `Mutex`, no `sending` init — the plain stored-property init compiles). This is the documented ``NebulaMemoryLogHandler`` precedent: the **only** `@unchecked` type in the layer, "justified … because it is a reference type, not a Nebula-defined value type." The binding forbids `@unchecked` on **value** types; a once-assigned, immutable, system-owned reference behind an audited `@unchecked` boundary is the permitted exception. The box crosses isolation, the façade then holds `Mutex<[String: NebulaBGTaskBox]>` (Sendable boxes → Sendable dictionary → Sendable `Mutex`), and the façade's `Sendable` conformance is **derived** — no `@unchecked` on the façade. The ``NebulaBackgroundTask`` handle's closures capture the **Sendable façade + identifier** (never the `BGTask`), reach the box via the façade's `Mutex`, and call the system task's lifecycle methods.

### `submit`: iOS-27 async + iOS-26 fallback

The `submit(_:)` requirement has a dual path, warning-clean under the Nebula `.v26` floor:

- **iOS-27 async** — `BGTaskScheduler.shared.submitTaskRequest(_:) async throws` (an OS-27 symbol) is gated `#if swift(>=6.4)` (absent from the Xcode 26.4 / Swift 6.3 SDK) + a runtime `if #available(iOS 27, tvOS 27, visionOS 27, *)`.
- **iOS-26 fallback** — the deprecated sync `BGTaskScheduler.shared.submit(_:)` (`submitTaskRequest:error:`, deprecated iOS 27). Deprecation warnings fire only when the deployment target ≥ the obsoleted version (`27 > 26`), so under `.v26` the fallback is **warning-clean** and keeps the façade's headline capability usable on Nebula's own floor.

### Testability constraint

Every `BackgroundTasks` SDK type is `API_UNAVAILABLE(macos)`. `swift test` runs on the **macOS host**, where none of them compile. So the all-5 value types / port / config / error are tested on macOS; the façade and the SDK-mapping round-trip are gated `#if !os(macOS) && !os(watchOS)` — they **compile** on iOS/tvOS/visionOS (verified via `xcodebuild`) but are dead code on the macOS test host. `BGTaskScheduler.shared` is non-functional in a headless test bundle (no app context — the ``NebulaUNNotificationCenter`` lesson), so the register/submit/cancel integration is a documented limitation: the port seam (a fake conformer) and the type-level conformance check prove the architecture; the mapping helpers round-trip through constructible `BGAppRefreshTaskRequest` / `BGProcessingTaskRequest`.

### What is deferred

- ``NebulaBackgroundTaskKind``/`processing` continued-processing (`BGContinuedProcessingTask` — iOS-26-only, `API_UNAVAILABLE` on the other four platforms: request subclass + submission strategy + resources + `NSProgressReporting` + `supportedResources`) → N15c.
- `registerForRemoteNotifications` (APNs token registration — `UIApplication` / `NSApplication` app-lifecycle).
- The unified ``NebulaPermissionStatus`` request port (AV / CoreLocation / Photos / ATT adapters).

## Topics

### Port
- ``NebulaBackgroundTaskScheduler``
- ``NebulaBackgroundTaskScheduler/register(_:)``
- ``NebulaBackgroundTaskScheduler/submit(_:)``
- ``NebulaBackgroundTaskScheduler/cancel(_:)``
- ``NebulaBackgroundTaskScheduler/cancelAll()``
- ``NebulaBackgroundTaskScheduler/pendingRequests()``

### Concrete façade
- ``NebulaBGTaskScheduler``

### Launch-time handle
- ``NebulaBackgroundTask``
- ``NebulaBackgroundTask/complete(success:)``
- ``NebulaBackgroundTask/onExpiration(_:)``

### Value types
- ``NebulaBackgroundTaskRequest``
- ``NebulaBackgroundTaskKind``

### Configuration
- ``NebulaBackgroundTaskConfiguration``
- ``NebulaBackgroundTaskConfig``

### Layer errors
- ``NebulaBackgroundTaskError``
# Notifications

A `Sendable` scheduling/authorization port over `UserNotifications`, a `final class` delegate-adapter façade that conforms to the port **and** to `UNUserNotificationCenterDelegate`, and `@Sendable` callback handlers held in a `Mutex`-backed configuration.

## Overview

`UNUserNotificationCenter` and `import UserNotifications` are available on all five Nebula platforms (iOS, macOS, tvOS, watchOS, visionOS), so this surface is **all-5** — no `#if canImport` and no per-platform `@available` gate on the framework itself. The scheduling surface (request authorization, schedule, cancel, enumerate pending) is the testable seam; the delegate callback surface (foreground presentation, tap response) is the adapter that forwards to `@Sendable` handlers.

- ``NebulaNotificationCenter`` — the **port**, a `Sendable` protocol with five requirements (``NebulaNotificationCenter/requestAuthorization(options:)``, ``NebulaNotificationCenter/add(_:)``, ``NebulaNotificationCenter/cancel(_:)``, ``NebulaNotificationCenter/cancelAll()``, ``NebulaNotificationCenter/pendingRequests()``). The delegate handlers are **not** on the port — they live on the config.
- ``NebulaUNNotificationCenter`` — the concrete **façade**, a `final class` that conforms to ``NebulaNotificationCenter`` **and** to `UNUserNotificationCenterDelegate`. It installs itself as `UNUserNotificationCenter.current().delegate` in ``NebulaUNNotificationCenter/init(_:)`` and forwards the two delegate callbacks to the `@Sendable` handlers in its ``NebulaNotificationsConfiguration``.
- ``NebulaNotificationsConfiguration`` — the `@Sendable`-handler config (``NebulaNotificationsConfiguration/willPresent`` / ``NebulaNotificationsConfiguration/didReceive``), held in a `Mutex`; process-wide access via ``NebulaNotificationsConfig``.
- ``NebulaNotificationsError`` — the open-struct notification-layer error.

```swift
let center = NebulaUNNotificationCenter(
    .default.withDidReceive { response in
        // handle the tap
    }
)
let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
try await center.add(
    NebulaNotificationRequest(
        identifier: "reminder",
        content: NebulaNotificationContent(title: "Title", body: "Body"),
        trigger: .timeInterval(60)
    )
)
```

### Why a `final class` and not an actor

`UNUserNotificationCenterDelegate` is an `@objc` protocol backed by a **`weak` Obj-C reference** — a plain Swift class can't back a `weak` Obj-C ref, so the façade subclasses `NSObject` (the ``NebulaHTTPServer`` `Sendable final class` precedent gains an `NSObject` base here). The delegate methods are **synchronous Obj-C callbacks**, not `async` entry points; an actor would need `nonisolated` plus a `Mutex` anyway, so a `final class` with a `Mutex<NebulaNotificationsConfiguration>` is the honest shape. `Sendable` is **derived** (the only stored property is the `Mutex<Config>`, which is `Sendable` because the config is) — no `@unchecked`.

The `delegate` property is `weak`, so it auto-nils when the façade deallocates — there is no `deinit` (an explicit `delegate = nil` would clobber a replacement façade). The app's composition root must retain the façade for its lifetime.

### `.current()` called locally, not stored

`UNUserNotificationCenter` is non-`Sendable`, and `.current()` is a **shared singleton** — it cannot be `sending`-consumed (unlike ``NebulaDefaults``' `Mutex<UserDefaults>` + `sending` precedent). The façade therefore calls `UNUserNotificationCenter.current()` **locally inside each method** (no stored center); the local reference does not escape the method, so region isolation is satisfied. The singleton is set as the delegate once in `init`.

### tvOS: content-less notifications and the `#if !os(tvOS)` gate

`UNUserNotificationCenterDelegate.didReceive` and `UNNotificationResponse` are `API_UNAVAILABLE(tvos)`, and every user-facing `UNNotificationContent` property (`title` / `body` / `subtitle` / `userInfo`) is `API_UNAVAILABLE(tvos)`. An `@available(tvOS, unavailable)` **declaration** gate cannot override an already-unavailable protocol requirement ("cannot override 'userNotificationCenter' which has been marked unavailable"), and an `if #available(...)` **runtime** check cannot make an `unavailable` symbol compile ("'title' is unavailable in tvOS" — the `*` wildcard does **not** exclude tvOS for an `unavailable` symbol). The only compile-safe mechanism is **`#if !os(tvOS)`** — a compile gate that excludes the symbol from the tvOS build entirely.

This establishes the `#if !os(<platform>)` precedent for platform-`unavailable` SDK symbols, distinct from the `@available(<platform>, unavailable)` declaration gate (which declares a **Nebula** symbol unavailable on a platform) and from the `#if canImport(<framework>)` whole-file gate that a follow-up establishes for an absent framework. On tvOS: the `didReceive` override is absent (the requirement is unavailable there), and scheduled notifications carry a content-less `UNMutableNotificationContent` — the ``NebulaNotificationContent`` value is still all-5 (it is a Nebula value, not the SDK's); only the SDK touch is gated.

### Synchronous-returning handlers

The config handlers return **synchronously** (``NebulaNotificationsConfiguration/willPresent`` returns ``NebulaNotificationPresentationOptions``; ``NebulaNotificationsConfiguration/didReceive`` returns `Void`). This avoids capturing the SDK's non-`@Sendable` Obj-C completion handler inside a `@Sendable` closure — a Swift 6 strict-concurrency wall the completion-callback shape would hit. The façade invokes the handler, then resumes the SDK completion with the (synchronous) result itself.

### What is deferred

- The `.location` notification trigger (needs `import CoreLocation` plus a 3-platform gate) — only `.timeInterval` / `.calendar` ship now.
- `setBadgeCount` (watchOS unavailable), `setNotificationCategories` / `getDelivered*` / `removeDelivered*` (tvOS unavailable), `openSettingsFor` (watchOS + tvOS unavailable).
- The unified ``NebulaPermissionStatus`` request port (AV / CoreLocation / Photos / ATT adapters) — only the status **value** and the `UNAuthorizationStatus` bridge ship now; see <doc:ArchitecturePermissions>.
- ``NebulaBackgroundTask`` (background-task scheduling) — shipped in <doc:ArchitectureBackgroundTasks>. It establishes the **type-level `@available(macOS, unavailable) @available(watchOS, unavailable)` declaration gate** (the ``NebulaLogStoreExporter`` precedent), **not** a `#if canImport(BackgroundTasks)` whole-file gate — `BackgroundTasks.framework` is physically present on macOS/watchOS (so `canImport` is `true` there and gates nothing); only the symbols are `API_UNAVAILABLE`.

## Topics

### Port
- ``NebulaNotificationCenter``
- ``NebulaNotificationCenter/requestAuthorization(options:)``
- ``NebulaNotificationCenter/add(_:)``
- ``NebulaNotificationCenter/cancel(_:)``
- ``NebulaNotificationCenter/cancelAll()``
- ``NebulaNotificationCenter/pendingRequests()``

### Concrete façade
- ``NebulaUNNotificationCenter``

### Value types
- ``NebulaNotificationContent``
- ``NebulaNotificationTrigger``
- ``NebulaNotificationRequest``
- ``NebulaNotificationResponse``
- ``NebulaNotificationPresentationOptions``
- ``NebulaAuthorizationOptions``

### Configuration
- ``NebulaNotificationsConfiguration``
- ``NebulaNotificationsConfig``

### Layer errors
- ``NebulaNotificationsError``

### Permission status
- ``NebulaPermissionStatus``
# CloudKit-backed observability

Metrics, analytics, and performance sinks backed by a CloudKit sync port — opt-in via configuration, ready-to-wire, no third-party dependencies.

## Overview

Nebula ships an observability surface composed of ports + adapters, mirroring the
``NebulaPreferences`` / ``NebulaDefaults`` seam model. Four concerns map onto it:

- **Metrics** — ``NebulaMetrics`` (a `Sendable` port with one ``NebulaMetrics/record(_:)``
  requirement plus counter / histogram / gauge / timing default extensions) +
  ``NebulaMetricEvent`` / ``NebulaMetricValue`` + ``NebulaMetricsConfiguration`` +
  ``NebulaLocalMetrics``.
- **Analytics** — ``NebulaAnalytics`` (a `Sendable` port with one ``NebulaAnalytics/track(_:)``
  requirement plus track / screen / identify default extensions) + ``NebulaAnalyticsEvent`` +
  ``NebulaAnalyticsConfiguration`` + ``NebulaLocalAnalytics``.
- **Backend performance** — ``NebulaPerformanceSink`` routes each ``NebulaMeasureResult``
  from the Measure subsystem into ``NebulaMetricsConfiguration`` as a `.timing` event.
- **CloudKit sync** — ``NebulaCloudKitSync`` (a `Sendable` port with `sendChanges()` /
  `fetchChanges()`) + ``NebulaCloudKitConfiguration`` + ``NebulaCloudKitSyncEngine``
  (a `CKSyncEngine` wrapper).

Every configuration defaults to a capture-free no-op handler and `isEnabled = true` for
metrics/analytics (the fan-out target is app-supplied) and `isEnabled = false` for the
CloudKit sync path (a foundation does not implicitly hit the network). An app opts in at
the composition root:

```swift
// Route metrics + analytics into a buffer, then flush to CloudKit in batches.
let buffer = NebulaEventBuffer<NebulaMetricEvent>(batchSize: 100) { batch in
    Task { try? await sync.enqueue(batch) }   // app-owned CloudKit sink
}
NebulaMetricsConfig.set(
    .default.withHandler { event in buffer.append(event) }
)

// Route every timing result from Measure into Metrics.
NebulaMeasureConfig.set(
    .default.withHandler(NebulaPerformanceSink.handler(via: NebulaMetricsConfig.get()))
)

// Enable CloudKit sync.
NebulaCloudKitConfig.set(
    .default.withContainerIdentifier("iCloud.com.example.app")
            .withZoneName("Observability")
            .withEnabled(true)
)
```

### Why CloudKit is admissible in Nebula core

CloudKit is a non-UI Apple framework available on all 5 platforms (iOS / macOS / tvOS /
watchOS / visionOS). Verified against the Xcode 27 Beta 3 `CloudKit.swiftmodule`
`.swiftinterface`: `CKContainer`, `CKDatabase`, and `CKSyncEngine` are clean `Sendable`
(no `@unchecked`), with `CKSyncEngine` `@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)`
+ visionOS via the trailing `*` — all below Nebula's `.v26` floor, so **no `@available` gate
and no `#if os()`** are needed for the core sync path. The `@unchecked Sendable` CK types
(`CKRecord`, `CKQuery`, `CKShare`, …) are **Apple classes**, not Nebula value types, so the
binding's "no `@unchecked` on Nebula-defined value types" rule does not forbid them; they are
handled at the adapter boundary (copy into Sendable Nebula values, the
``NebulaLogStoreExporter`` precedent).

### Why a `Mutex` and a `final class`

``NebulaEventBuffer`` wraps a `Mutex<[Event]>` and is a `final class` so the `~Copyable`
`Mutex` is absorbed behind a copyable, `Sendable` reference (derived, **no `@unchecked`**).
The flush handler is invoked **outside** the lock (drain under the lock, hand off after) to
avoid reentrancy. ``NebulaLocalMetrics`` / ``NebulaLocalAnalytics`` are the same shape —
`final class` + `Mutex<[Event]>`.

``NebulaMetricsConfiguration`` / ``NebulaAnalyticsConfiguration`` are `Sendable` value types
that store a `@Sendable` handler, so they are `Sendable` **only** (not `Equatable` — a
closure is not `Equatable`, mirroring ``NebulaMeasureConfiguration``). ``NebulaCloudKitConfiguration``
stores no handler (sync is stateful, not a fan-out) and so is `Sendable, Equatable`.

``NebulaCloudKitSyncEngine`` is a `final class` whose `Sendable` is derived: `CKSyncEngine`
is a clean `final class : Sendable`, the Nebula config is a `Sendable` value, and the
Nebula-owned `Delegate` adapter is a `final class` whose stored properties are `@Sendable`
closures (SE-0302 final-class rule). The `CKContainer` / `CKDatabase` are constructed
locally in `init`, used to build the `CKSyncEngine.Configuration`, and discarded — they are
not stored on the conformer, so their preconcurrency Sendability never reaches a Nebula
`Sendable` derivation. `sendChanges()` / `fetchChanges()` gate on
``NebulaCloudKitConfiguration/isEnabled``.

## Topics

### Metrics
- ``NebulaMetrics``
- ``NebulaMetricEvent``
- ``NebulaMetricKind``
- ``NebulaMetricValue``
- ``NebulaMetricsConfiguration``
- ``NebulaMetricsConfig``
- ``NebulaLocalMetrics``
- ``NebulaEventBuffer``

### Analytics
- ``NebulaAnalytics``
- ``NebulaAnalyticsEvent``
- ``NebulaAnalyticsConfiguration``
- ``NebulaAnalyticsConfig``
- ``NebulaLocalAnalytics``

### Performance sink
- ``NebulaPerformanceSink``

### CloudKit sync
- ``NebulaCloudKitSync``
- ``NebulaCloudKitSyncEngine``
- ``NebulaCloudKitConfiguration``
- ``NebulaCloudKitEnvironment``
- ``NebulaCloudKitConfig``

### CloudKit preferences (N19d)
- ``NebulaCloudKitPreferences``
- ``NebulaCloudKitKVChange``

### CloudKit feature flags (N19d)
- ``NebulaCloudKitFeatureFlags``

A ``NebulaRemoteFeatureFlags`` conformer backed by a local cache refreshed from
CloudKit — the read-only counterpart to ``NebulaCloudKitPreferences``.
``value(forKey:)`` serves the local `Mutex<[String: NebulaFlagValue]>` cache
(synchronous, the ``NebulaFeatureFlags`` contract); ``refresh()`` pulls
`NebulaFlag` records from the configured database and replaces the cache, leaving
it unchanged on failure (the port contract — reads keep resolving to the last good
fetch). The conformer is **read-only**: the port has no write requirement, and
writing flag records to CloudKit is app-owned. The CloudKit boundary is stateless
per call (the ``NebulaKeychain`` precedent) — no `CKDatabase` is stored, so
`Sendable` is derived with **no `@unchecked`** (config `Sendable` struct +
`Mutex` absorbed behind the `final class` + `@Sendable` fetch closure). The fetch
is injectable, so the cache/refresh contract is unit-tested without CloudKit I/O;
the default fetch (``NebulaCloudKitFeatureFlags/defaultFetch(configuration:)``) is
compile-verified (runtime needs an iCloud entitlement + account). Flag records are
mapped to/from ``NebulaFlagValue`` by ``NebulaCloudKitFeatureFlags/encode(_:into:)``
/ ``NebulaCloudKitFeatureFlags/decode(from:)`` — a `kind` tag + a per-kind field,
pure and unit-testable with an in-memory `CKRecord` (no iCloud).
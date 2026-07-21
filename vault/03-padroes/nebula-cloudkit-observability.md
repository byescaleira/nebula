---
tags: [pattern, architecture, cloudkit, observability, metrics, analytics, feature-flags]
aliases: [nebula-cloudkit, nebula-observability, cloudkit-adapter]
related: [nebula-feature-flags, nebula-app-readiness-research, nebula-swift6-concurrency, nebula-clean-architecture, nebula-standardize-measure]
---

# Nebula — CloudKit-backed observability suite (metrics / analytics / feature flags / performance)

> **Status: Proposed (design, on branch `worktree-cloudkit-observability-design`).** Source of truth = root docs (`ARCHITECTURE.md`, `DECISIONS.md`, `ROADMAP.md`); this note is the synthesis. The CloudKit admissibility facts here were verified against the `.swiftinterface` (Xcode 27 Beta 3 / Swift 6.4) — the authoritative ground truth per `CLAUDE.md`.

## The question

> *"Pensando em métricas, feature flags, analytics, desempenho em backend, gostaria que o Nebula oferecesse toda a interface e código pronto para configurar isso com o CloudKit da Apple — qualquer app que usar o Nebula pode optar por ligar. Dá pra fazer isso?"*

**Short answer: yes.** CloudKit is admissible in Nebula core (non-UI Apple framework, available on all 5 platforms, core sync types clean `Sendable`). The only correction to prior research is the Sendability premise (see [[#Correção ao veredicto anterior]]).

## What Nebula already ships (the seams a CloudKit adapter fills)

The Clean Architecture toolkit already defines the ports an observability backend needs. A CloudKit adapter is *another conformer*, not new architecture:

| Concern | Existing port / config | File | CloudKit adapter role |
|---|---|---|---|
| Feature flags | `NebulaRemoteFeatureFlags` (`refresh() async throws`) refines `NebulaFeatureFlags` (`value(forKey:) -> NebulaFlagValue?`) | `Architecture/FeatureFlags/NebulaRemoteFeatureFlags.swift` | sync flags from a `CKRecord` zone; serve last-fetched via `value(forKey:)`; `refresh()` runs `CKSyncEngine.fetchChanges` |
| Feature flags composite | `NebulaCompositeFeatureFlags` (first-non-nil, `[localOverrides, remote, builtInDefaults]`) | `Architecture/FeatureFlags/NebulaCompositeFeatureFlags.swift` | the CloudKit conformer slots in as the `remote` source |
| Timing / signposts | `NebulaMeasureConfiguration` (clock + signposter + `@Sendable` handler, `measure`/`bench`) | `Measure/NebulaMeasureConfiguration.swift` | a `NebulaPerformanceSink` flushes `NebulaMeasureResult` batches to CloudKit |
| KV persistence port | `NebulaPreferences` (`data(forKey:)`/`setData(_:forKey:)`/`remove(forKey:)`) + `Codable`/`RawRepresentable` default extensions | `Architecture/Preferences/NebulaPreferences.swift` | a `NebulaCloudKitPreferences` conformer syncs a KV store via CloudKit (flag overrides, local analytics batch buffer) |
| Config-struct pattern | `NebulaXConfiguration: Sendable` + `@Sendable` handler + `.with*` + `NebulaXConfig` (`Mutex` accessor) | `Logging/…`, `Errors/…`, `Measure/…`, `Gateway/…`, `Registry/…` | mirror for `NebulaMetricsConfiguration` / `NebulaAnalyticsConfiguration` / `NebulaCloudKitConfiguration` |

**Net new surface** is two ports + three configs + one CloudKit glue port + the CloudKit conformers. Everything else composes existing types.

## The four concerns, mapped

### 1. Metrics — NEW port `NebulaMetrics`
A `Sendable` port (one low-level requirement + default-extension ergonomics, mirroring `NebulaFeatureFlags`):

```swift
public protocol NebulaMetrics: Sendable {
    func record(_ event: NebulaMetricEvent)  // the single requirement
}
public extension NebulaMetrics {
    func increment(_ name: String, by: Int = 1)         // counter
    func observe(_ name: String, value: Double)         // histogram
    func gauge(_ name: String, value: Double)           // gauge
    func timing(_ name: String, duration: Duration)     // from NebulaMeasureResult
}
```

`NebulaMetricEvent` — a `Sendable, Equatable` value (`name`, `kind: .counter/.histogram/.gauge/.timing`, `value: Double`, `timestamp: Date`, `attributes: [String: NebulaMetricValue]`). `NebulaMetricValue` mirrors `NebulaFlagValue` (`.bool/.string/.int/.double/.json`).

**Config:** `NebulaMetricsConfiguration: Sendable` (NOT `Equatable` — stores `@Sendable` handler) carrying `isEnabled`, `batchSize`, `flushInterval`, `handler: @Sendable ([NebulaMetricEvent]) -> Void` (batch fan-out), `.with*` builders, `static let default`, process-wide `NebulaMetricsConfig` (`Mutex` accessor). Entry point `record(_:)` on the config buffers then flushes on `batchSize`/`flushInterval`.

### 2. Analytics — NEW port `NebulaAnalytics`
A `Sendable` event-ingestion port:

```swift
public protocol NebulaAnalytics: Sendable {
    func track(_ event: NebulaAnalyticsEvent)  // the single requirement
}
public extension NebulaAnalytics {
    func track(_ name: String, properties: [String: NebulaMetricValue] = [:])
    func screen(_ name: String, properties: [String: NebulaMetricValue] = [:])
    func identify(_ userID: String, properties: [String: NebulaMetricValue] = [:])
}
```

`NebulaAnalyticsEvent` — `Sendable, Equatable` (`name`, `properties`, `timestamp`). **Config:** `NebulaAnalyticsConfiguration: Sendable` + `@Sendable ([NebulaAnalyticsEvent]) -> Void` batch handler + `.with*` + `NebulaAnalyticsConfig` accessor. Same buffering model as metrics — analytics/metrics share a generic `NebulaEventBuffer<T: Sendable>` behind the scenes (a `final class` wrapping `Mutex<[T]>` + a flush `Task`), so the two configs are siblings, not duplicated code.

### 3. Feature flags — EXISTING port, new CloudKit conformer
No new port needed. A `NebulaCloudKitFeatureFlags: NebulaRemoteFeatureFlags` conformer:
- holds a `NebulaCloudKitConfiguration` + a backing `NebulaLocalFeatureFlags` cache;
- `value(forKey:)` reads the cache (last-fetched);
- `refresh() async throws` runs `CKSyncEngine.fetchChanges` (or a `CKQueryOperation` against a `FeatureFlags` record zone), parses `CKRecord` payloads into `NebulaFlagValue`, and updates the cache atomically. A failed refresh leaves the cache unchanged (the port contract).

The app wires it into `NebulaCompositeFeatureFlags([localOverrides, cloudKitFlags, builtInDefaults])`.

### 4. Performance (backend) — reuse `NebulaMeasureConfiguration` + NEW sink
Timing/signpost already ships. The backend piece is a `NebulaPerformanceSink` that:
- subscribes to the `NebulaMeasureConfiguration.handler` fan-out (`handler = { result in metricsConfig.record(.timing(result.name, result.perIteration)) }`);
- the metrics port then batches and uploads to CloudKit.

So "backend performance" = `NebulaMeasureConfiguration` (capture) → `NebulaMetrics` (route) → CloudKit (sink). No new timing API.

## The CloudKit glue port

```swift
public struct NebulaCloudKitConfiguration: Sendable, Equatable {
    public let containerIdentifier: String?        // nil → CKContainer.default()
    public let environment: CKContainer.Environment  // .private (default) / .public / .shared
    public let zoneName: String                    // default "NebulaObservability"
    public let isEnabled: Bool
    // NO handler — CloudKit sync is stateful, not a fan-out; the port owns the engine.
    public static let `default` = NebulaCloudKitConfiguration()
    // .withContainerIdentifier / .withEnvironment / .withZoneName / .withEnabled
}
public enum NebulaCloudKitConfig { /* Mutex<NebulaCloudKitConfiguration> accessor, no gate */ }

/// The CloudKit sync port — wraps CKSyncEngine (clean Sendable) behind a
/// Nebula-owned Sendable boundary.
public protocol NebulaCloudKitSync: Sendable {
    func sendChanges() async throws        // upload pending batches
    func fetchChanges() async throws      // pull flag/remote-config changes
}
```

`NebulaCloudKitSyncEngine: NebulaCloudKitSync` — a `final class` (absorbs `~Copyable`/stateful sync) wrapping `CKSyncEngine`. `CKSyncEngine` is `final class : Sendable` with async `fetchChanges(_:)`/`sendChanges(_:)` and a `delegate: any CKSyncEngineDelegate` — the delegate bridge is a Nebula `@Sendable` adapter that copies `CKRecord` → Sendable payloads immediately (the `NebulaLogStoreExporter` precedent: `OSLogEntry` not Sendable → copy into `NebulaLogStoreEntry`).

## CloudKit admissibility — verified facts (Xcode 27 Beta 3 / Swift 6.4 `.swiftinterface`)

`CloudKit.swiftmodule/arm64e-apple-ios.swiftinterface` — cite by line:

- **CKSyncEngine** — `final public class CKSyncEngine : Swift::Sendable` (L1615-1617), clean `Sendable` (NO `@unchecked`), `@available(macOS 14.0, …, iOS 17.0, tvOS 17.0, watchOS 10.0, *)` (L1615) → all 5 platforms (visionOS via trailing `*`); async `fetchChanges(_:)`/`sendChanges(_:)` (L1629-1630); `state`, `stateSerialization` for resumable sync. This is the sync primitive.
- **CKContainer** — base availability `@available(macOS 10.12, …, iOS 9.3, tvOS 9.2, watchOS 3.0, *)` (L27, visionOS via `*`). Used as a `@Sendable (_ configuredContainer: CKContainer) async throws -> R` closure parameter (L46) → `Sendable`. The whole 5-platform set.
- **CKDatabase** — same shape; stored as a `let` property of the clean-`Sendable` `CKSyncEngine` (`final public var database: CKDatabase`, L1620-1621) → CKDatabase is `Sendable` (a clean-Sendable class cannot store a non-Sendable `var`). Used as `@Sendable` closure param (L449).
- **CKError** — clean `Sendable`.
- **`@unchecked Sendable` CK types** (still): `CKRecord`, `CKQuery`, `CKOperation`, `CKOperationGroup`, `CKSubscription`, `CKQuerySubscription`, `CKRecordZoneSubscription`, `CKDatabaseSubscription`, `CKFetchRecordZoneChangesOperation`, `CKQueryOperation`, `CKShare`, `CKRecordZone`, `CKUserIdentity`, `CKNotification`, `CKAsset`, `CKAllowedSharingOptions`, `CKOperation.Configuration`. These are the value-bearing records/queries.

### Implication for the binding's "no `@unchecked` on Nebula-defined types"
The binding forbids `@unchecked Sendable` on **Nebula value types**. CK* `@unchecked` types are **Apple classes**, not Nebula types. The documented escape hatch applies: a **`final class @unchecked Sendable` plain-`let` box** around a non-Sendable Apple class delivered through a `@Sendable` boundary — the `NebulaMemoryLogHandler` precedent, see [[non-sendable-system-class-via-unchecked-ref-box]]. So `CKRecord` payloads are copied into Sendable Nebula values (`NebulaFlagValue`, `NebulaAnalyticsEvent`) at the adapter boundary and never stored as raw `CKRecord` in a `Mutex`. The adapter itself is a `final class` whose `Sendable` is derived where it holds only clean-Sendable fields (`CKContainer`/`CKDatabase`/`CKSyncEngine` + a `Mutex<[SendableValue]>` buffer); `@unchecked` is used ONLY on the box types wrapping `@unchecked`-Sendable CK classes, never on a Nebula struct.

## The opt-in model (the "código pronto" the user wants)

Nebula ships the adapters **ready but off by default** — every config defaults to a capture-free no-op handler and `isEnabled: false` for the CloudKit path. An app turns it on at the composition root, exactly like the existing configs:

```swift
// app @main / App.init
let cloud = NebulaCloudKitConfiguration()
    .withContainerIdentifier("iCloud.com.example.app")
    .withZoneName("Observability")
    .withEnabled(true)
NebulaCloudKitConfig.set(cloud)

let sync = NebulaCloudKitSyncEngine(config: cloud)   // owned by the app

NebulaMetricsConfig.set(
    .default.withEnabled(true).withHandler { events in
        Task { try? await sync.enqueue(.metrics(events)) }  // batch → CKModifyRecordsOperation
    }
)
NebulaAnalyticsConfig.set(
    .default.withEnabled(true).withHandler { events in
        Task { try? await sync.enqueue(.analytics(events)) }
    }
)
NebulaMeasureConfig.set(
    .default.withEnabled(true).withHandler { result in
        NebulaMetricsConfig.record(.timing(result.name, result.perIteration))
    }
)

// feature flags — CloudKit as the remote source
let remote = NebulaCloudKitFeatureFlags(config: cloud, sync: sync)
let flags = NebulaCompositeFeatureFlags([NebulaLocalFeatureFlags(), remote, defaults])
```

No environment, no singletons beyond the existing `Nebula*Config` accessors. Explicit-parameter DI still works for tests (pass a `NebulaMetricsConfiguration` / a fake `NebulaCloudKitSync`).

## Batch upload shape (analytics/metrics → CloudKit)

- Events buffer in a `NebulaEventBuffer<T>` (`final class` + `Mutex<[T]>`, flush `Task.detached` on `batchSize` or `flushInterval`) — the `NebulaHTTPServer.OnceFlag` once-token pattern for the flush gate.
- On flush, the CloudKit sink maps each `NebulaAnalyticsEvent`/`NebulaMetricEvent` → a `CKRecord` (recordType `NebulaAnalyticsEvent`/`NebulaMetric`, `recordID` = `UUID.random()`-derived `CKRecord.ID`), and runs a `CKModifyRecordsOperation` (`.saveIfNone` for idempotent upload) against the configured zone.
- `CKSyncEngine` manages the change-token / delta sync for the **flag** direction (pull); the upload direction (push) is a plain `CKModifyRecordsOperation` (the engine's `sendChanges` can also drive it, but a direct op is simpler for append-only telemetry).
- Telemetry records go to the **private** database by default (`CKContainer.Environment.private`); a `withEnvironment(.public)` makes them shareable for a team dashboard. **Never** PII in `.public`.

## Risks / open verification (flagged, not yet compiled)

- **`CKSyncEngineDelegate` bridging across isolation** — the delegate methods are called on CloudKit's queue; the Nebula `@Sendable` adapter must copy `CKRecord` payloads into Sendable Nebula values synchronously and forward via `Task.detached`. Pattern validated by `NebulaHTTPGateway.send` (`Task.detached { [self] in … }` to avoid hopping onto a caller actor).
- **`CKModifyRecordsOperation` Sendability** — it is `@unchecked Sendable`; the op is constructed per-flush (the `NebulaKeychain` stateless-per-call precedent), never stored long-term in a `Mutex`, so the `@unchecked` surface is transient.
- **watchOS quota / background constraints** — CloudKit on watchOS works but with tighter quotas and no background-daemon guarantees; the flush interval must be conservative and `isEnabled` should default `false` on watchOS via `#if os(watchOS)` in the example, not by gating the type (the type compiles on all 5).
- **`containerIdentifier` requires an entitlement** — a Nebula sample can't ship a working CloudKit container; the runnable example is app-owned (the `MeridianExample` precedent). The Nebula side ships compile-verified against the SDK; the live container is the app's.
- **visionOS availability** — verified available (trailing `*` on `CKContainer`/`CKSyncEngine` availability); confirm at compile time on the visionOS SDK (the `OSLogStore.Scope.system` caution).

## Wave proposal

`ROADMAP.md` **Wave N19 — CloudKit-backed observability suite**:
- N19a — `NebulaMetrics` port + `NebulaMetricEvent`/`NebulaMetricValue` + `NebulaMetricsConfiguration`/`NebulaMetricsConfig` + in-memory `NebulaLocalMetrics` + `NebulaEventBuffer<T>`.
- N19b — `NebulaAnalytics` port + `NebulaAnalyticsEvent` + `NebulaAnalyticsConfiguration`/`NebulaAnalyticsConfig` + in-memory façade (reuses `NebulaEventBuffer`).
- N19c — `NebulaCloudKitConfiguration`/`NebulaCloudKitConfig` + `NebulaCloudKitSync` port + `NebulaCloudKitSyncEngine` (`CKSyncEngine` wrapper + `@Sendable` delegate bridge).
- N19d — `NebulaCloudKitFeatureFlags` (`NebulaRemoteFeatureFlags` conformer, pull via `fetchChanges`) + `NebulaCloudKitPreferences` (`NebulaPreferences` conformer).
- N19e — `NebulaPerformanceSink` (wires `NebulaMeasureConfiguration.handler` → `NebulaMetrics`) + the analytics/metrics → `CKModifyRecordsOperation` flush path.
- N19f — DocC `ArchitectureCloudKit.md` article + runnable app-owned example (extend `MeridianExample` or new `NebulaCloudKitExample`).

## Correção ao veredicto anterior

[[nebula-app-readiness-research]] linha CloudKit dizia: **Defer (sibling)** — *"`CK*` majoritariamente non-Sendable/`@unchecked`; `CKSyncEngine` (iOS 17) é o único Sendable limpo; pesado"*. Essa premissa estava baseada num snapshot mais antigo. Verificação contra o `.swiftinterface` Xcode 27 Beta 3 / Swift 6.4 mostra que **`CKContainer`, `CKDatabase` e `CKSyncEngine` são `Sendable` limpos** (não `@unchecked`); apenas `CKRecord`/`CKQuery`/`CKOperation`/`CKShare`/`CKRecordZone`/`CKAsset` etc. continuam `@unchecked Sendable` — e esses são classes Apple, não tipos Nebula, então o pattern do `final class @unchecked Sendable` box (precedente `NebulaMemoryLogHandler`) resolve dentro das regras do `CLAUDE.md`. Veredicto corrigido: **CloudKit é admissível no core do Nebula** (Foundation-tier, 5-platform, sem gate de plataforma para o caminho de sync), não exige sibling. A linha CloudKit em [[nebula-app-readiness-research]] foi atualizada para refletir isto.

## Related

- [[nebula-feature-flags]] — the existing port family this builds on
- [[nebula-standardize-measure]] — `NebulaMeasureConfiguration`, the performance capture side
- [[nebula-swift6-concurrency]] — `Mutex`/`@Sendable`/`@unchecked`-box rules applied here
- [[nebula-clean-architecture]] — port + adapter + composition-root wiring
- [[non-sendable-system-class-via-unchecked-ref-box]] — the escape hatch for `@unchecked` CK classes
- [[nebula-app-readiness-research]] — corrected CloudKit row
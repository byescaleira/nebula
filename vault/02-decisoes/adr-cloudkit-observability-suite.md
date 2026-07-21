---
tags: [adr, decision, cloudkit, observability]
aliases: [ADR-CloudKit-Observability, nebula-cloudkit-adr]
related: [nebula-cloudkit-observability, nebula-app-readiness-research, nebula-feature-flags, nebula-swift6-concurrency]
status: Proposed
date: 2026-07-20
---

# ADR — CloudKit-backed observability suite (metrics / analytics / feature flags / performance)

## Context

Owner asked whether Nebula can ship a ready-to-configure observability surface — **metrics, feature flags, analytics, backend performance — backed by Apple CloudKit**, so any app consuming Nebula can opt in by flipping the configuration (Nebula provides the interface and the adapter code; the app supplies the CloudKit container).

Prior research ([[nebula-app-readiness-research]]) had deferred CloudKit to a **sibling package** with the premise: *"`CK*` majoritariamente non-Sendable/`@unchecked`; `CKSyncEngine` (iOS 17) é o único Sendable limpo; pesado"*.

## Decision

**CloudKit is admissible in Nebula core — not a sibling.** Build the observability suite as ports + CloudKit adapters inside Nebula, opt-in via the existing `Nebula*Config` pattern.

Verified against the authoritative `.swiftinterface` (Xcode 27 Beta 3 / Swift 6.4, `CloudKit.swiftmodule/arm64e-apple-ios.swiftinterface`):

- `CKSyncEngine` — `final public class … : Swift::Sendable`, **clean** (no `@unchecked`), `@available(macOS 14, …, iOS 17, tvOS 17, watchOS 10, *)` → all 5 platforms (visionOS via `*`), async `fetchChanges`/`sendChanges`.
- `CKContainer`, `CKDatabase`, `CKError` — **clean `Sendable`** (CKContainer/CKDatabase used as `@Sendable` closure params; CKSyncEngine stores a `CKDatabase` as a clean-`Sendable` class var). Available all 5 platforms.
- `@unchecked Sendable` remains on `CKRecord`, `CKQuery`, `CKOperation`, `CKSubscription`, `CKShare`, `CKRecordZone`, `CKAsset`, `CKOperation.Configuration`, etc. — these are **Apple classes**, not Nebula value types, so the binding's "no `@unchecked` on Nebula-defined value types" does NOT forbid them. They are handled by the documented `final class @unchecked Sendable` plain-`let` box (precedent `NebulaMemoryLogHandler`; see [[non-sendable-system-class-via-unchecked-ref-box]]) and copied into Sendable Nebula values at the adapter boundary (precedent `NebulaLogStoreExporter` copying `OSLogEntry` → `NebulaLogStoreEntry`).

The prior premise was a snapshot from an older SDK; the current authoritative interface makes the core sync types clean `Sendable`. **Corrected verdict: CloudKit in Nebula core.**

## Surface

- **Feature flags** — reuse the existing `NebulaRemoteFeatureFlags` port (`refresh() async throws`); add a `NebulaCloudKitFeatureFlags` conformer (pull via `CKSyncEngine.fetchChanges` → `NebulaFlagValue`). No new port.
- **Metrics** — NEW `NebulaMetrics` port (`record(_:)` + counter/histogram/gauge/timing default extensions) + `NebulaMetricEvent`/`NebulaMetricValue` + `NebulaMetricsConfiguration`/`NebulaMetricsConfig` + in-memory `NebulaLocalMetrics` + a generic `NebulaEventBuffer<T>`.
- **Analytics** — NEW `NebulaAnalytics` port (`track(_:)` + track/screen/identify default extensions) + `NebulaAnalyticsEvent` + `NebulaAnalyticsConfiguration`/`NebulaAnalyticsConfig` (reuses `NebulaEventBuffer`).
- **Backend performance** — reuse `NebulaMeasureConfiguration` (capture); add a `NebulaPerformanceSink` wiring `NebulaMeasureConfiguration.handler` → `NebulaMetrics` → CloudKit flush. No new timing API.
- **CloudKit glue** — `NebulaCloudKitConfiguration` (containerIdentifier/environment/zoneName/isEnabled; `Sendable, Equatable`, no handler — sync is stateful) + `NebulaCloudKitConfig` accessor + `NebulaCloudKitSync` port (`sendChanges`/`fetchChanges`) + `NebulaCloudKitSyncEngine` (`final class` wrapping `CKSyncEngine` + a `@Sendable` delegate bridge). Telemetry push via `CKModifyRecordsOperation` (constructed per-flush, stateless-per-call like `NebulaKeychain`).

## Opt-in model

Every config defaults to a capture-free no-op handler and `isEnabled: false` for the CloudKit path. The app turns it on at the composition root via `Nebula*Config.set(_:)` (or explicit-param DI for tests), supplying `containerIdentifier` + entitlements. Nebula ships compile-verified adapters; the live CloudKit container is the app's (the `MeridianExample` precedent — a Nebula sample can't ship a working container). `dependencies: []` stays pristine (CloudKit is a system framework, not an SPM dep).

## Consequences

- **+** One `import Nebula` gives an app the full CloudKit-backed observability stack; opt-in is config-only.
- **+** Feature flags reuse the existing port — no API duplication; the CloudKit conformer is just another `NebulaRemoteFeatureFlags`.
- **+** `dependencies: []` preserved; CloudKit admissible as a non-UI Apple framework on all 5 platforms.
- **−** Adds CloudKit surface to Nebula (heavier than a pure-Foundation port). Mitigated by: adapters off by default; the heavy `@unchecked` CK value types isolated behind `final class` boxes + immediate copy-to-Sendable.
- **−** `CKSyncEngineDelegate` bridge and `CKModifyRecordsOperation` Sendability need compile verification on all 5 platform SDKs (flagged in [[nebula-cloudkit-observability]] risks).
- **−** Runnable example is app-owned (entitlement-gated container); Nebula ships compile-verified code, not a live demo.

## Status

**Proposed.** Implementation planned as Roadmap **Wave N19** (N19a metrics → N19b analytics → N19c CloudKit glue → N19d feature-flag/preferences conformers → N19e performance sink → N19f DocC + example). NOT yet compiled — the source scaffolding depends on the FeatureFlags port, which is currently uncommitted in the owner's working copy (N9–N18 WIP); N19 should branch from the owner's current state once that WIP is committed.

## Root-doc follow-up (owner action)

When merging this design into the working copy:
- `DECISIONS.md` — add the ADR row (this note's content, condensed) to the table tail.
- `ARCHITECTURE.md` — add the `CloudKit/` (or `Observability/`) subtree row + prose.
- `ROADMAP.md` — add Wave N19 after the current latest wave.
- `CHANGELOG.md` — add the entry under the next version.
- `vault/03-padroes/nebula-app-readiness-research.md` — replace the CloudKit row's verdict from "Defer (sibling)" to "Façade in Nebula core (Wave N19)" with the corrected Sendability facts. (This row is mid-flight/uncommitted in the owner working copy, so the correction is applied there, not on this branch.)

## Related

- [[nebula-cloudkit-observability]] — full design (the pattern detail)
- [[nebula-app-readiness-research]] — prior verdict being corrected
- [[nebula-feature-flags]] — the existing port family
- [[nebula-swift6-concurrency]] — `@unchecked`-box rule applied
- [[non-sendable-system-class-via-unchecked-ref-box]] — escape hatch for `@unchecked` CK classes
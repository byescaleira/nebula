---
tags: [adr, decision, cloudkit, observability]
aliases: [ADR-CloudKit-Observability, nebula-cloudkit-adr]
related: [nebula-cloudkit-observability, nebula-app-readiness-research, nebula-feature-flags, nebula-swift6-concurrency]
status: Implemented (N19a–e complete; shipped 0.17.0)
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

**Implemented — Wave N19 complete (N19a–e), shipped as Nebula 0.17.0 on `main` (merged PR #3 `worktree-cloudkit-observability-design`).** Wave N19 source compiled + tested clean across all 5 platforms:

- N19a Metrics — `NebulaMetricValue` / `NebulaMetricEvent` / `NebulaMetricKind` / `NebulaEventBuffer<Event>` / `NebulaMetrics` (port + counter/histogram/gauge/timing default exts) / `NebulaMetricsConfiguration` / `NebulaMetricsConfig` / `NebulaLocalMetrics`.
- N19b Analytics — `NebulaAnalyticsEvent` / `NebulaAnalytics` (port + track/screen/identify default exts) / `NebulaAnalyticsConfiguration` / `NebulaAnalyticsConfig` / `NebulaLocalAnalytics` (reuses `NebulaEventBuffer`).
- N19c CloudKit glue — `NebulaCloudKitEnvironment` / `NebulaCloudKitConfiguration` / `NebulaCloudKitConfig` / `NebulaCloudKitSync` (port + `sync()` default ext) / `NebulaCloudKitSyncEngine` (`CKSyncEngine` wrapper + `@Sendable` delegate adapter).
- N19e PerformanceSink — `NebulaPerformanceSink` (routes `NebulaMeasureResult` → `NebulaMetricsConfiguration`).
- N19d COMPLETE — `NebulaCloudKitPreferences` (conforms `NebulaPreferences`: local synchronous cache + an injectable async sink that flushes each `NebulaCloudKitKVChange` to CloudKit — default sink maps a key/value to a `CKRecord` in the configured zone, save/delete stateless per call, the `NebulaKeychain` precedent, no `CKDatabase` stored, `Sendable` derived with no `@unchecked`; plus `ensureZone()` / `refresh()` extras) **AND** `NebulaCloudKitFeatureFlags` (conforms `NebulaRemoteFeatureFlags`: read-only; `value(forKey:)` serves a local `Mutex<[String: NebulaFlagValue]>` cache; `refresh()` pulls `NebulaFlag` records and replaces the cache, leaving it unchanged on failure — the port contract; injectable `fetch`, default compile-verified; public `encode(_:into:)`/`decode(from:)` record codec — a `kind` tag + per-kind field, pure, unit-testable with an in-memory `CKRecord`, no iCloud). The earlier "N19d PARTIAL / deferred" status reflected `NebulaRemoteFeatureFlags` being uncommitted in the owner's working copy at PR-merge time; that port is now on `main`, so the conformer shipped in the same 0.17.0 release. CKDatabase-Sendability-when-stored was probe-verified (a `final class: Sendable { let db: CKDatabase }` derives Sendable cleanly), though both shipped conformers store no `CKDatabase` (stateless per-call boundary).
- N19f DocC — `ArchitectureCloudKitObservability.md` article shipped AND indexed in `Architecture.md` (after `ArchitectureBackgroundTasks`); the N19d remainder added the CloudKit feature-flags topics + prose.

Verification: `swift build` + `swift test` (963 tests / 194 suites, +55 over the 0.16.0 bundle) green with zero concurrency warnings; `swift build -c release` clean; adversarial verify workflow (binding/Sendable, CloudKit availability vs `.swiftinterface`, pattern fidelity) clean apart from 2 minor findings (both fixed: added `NebulaCloudKitSync.sync()` default extension, fixed a doc-comment indent). **Per-platform cross-compile confirmed**: `swift build --triple arm64-apple-tvos26.0` / `watchos26.0` / `xros26.0` all green (host macOS + iOS already green) — all 5 platforms compile the CloudKit path ungated, including both N19d conformers.

## Root-doc follow-up (done)

The root-doc governance landed with the 0.17.0 release:
- `DECISIONS.md` — N19 ADR row appended (Accepted).
- `ARCHITECTURE.md` — `Metrics/` + `Analytics/` + `CloudKit/` + `PerformanceSink` subtree row + structure tree + prose bullet.
- `ROADMAP.md` — `## Done (0.17.0 — CloudKit-backed observability)` section inserted; "Last updated" header refreshed.
- `CHANGELOG.md` — `## [0.17.0] - 2026-07-21` entry under `[Unreleased]`.
- `CLAUDE.md` — allowed-frameworks list += `CloudKit` (the corrected Sendability facts).
- `vault/03-padroes/nebula-app-readiness-research.md` — CloudKit row verdict corrected from "Defer (sibling)" to "Façade in Nebula core (Wave N19)", ✅ shipped 0.17.0.

## Related

- [[nebula-cloudkit-observability]] — full design (the pattern detail)
- [[nebula-app-readiness-research]] — prior verdict being corrected
- [[nebula-feature-flags]] — the existing port family
- [[nebula-swift6-concurrency]] — `@unchecked`-box rule applied
- [[non-sendable-system-class-via-unchecked-ref-box]] — escape hatch for `@unchecked` CK classes
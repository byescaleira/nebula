---
tags: [riscos, swift6, os, signpost, availability, nebula-27]
aliases: [OSMetricOperation internal, NebulaMetricOperation defer]
related: [[Home]], [[nebula-logging]], [[nebula-standardize-measure]]
status: open
---

# OSMetricOperation is internal to the os overlay

Gotcha: `OSMetricOperation` — the OS 26 signpost-metrics enum — is `@usableFromInline internal` in the `os` overlay. It **cannot be re-exported across module boundaries**, so a Nebula API that tried to surface it verbatim would not compile. Source of truth = the `os` overlay `.swiftinterface`; this note is synthesis.

## Constraint

If `NebulaSignposter` is to expose metric APIs (per-iteration sample aggregation, the signpost-metrics surface added in OS 26), Nebula cannot pass `OSMetricOperation` through. The enum's cases are visible to callers only via the `os` module's own API, not via a re-export.

## Resolution

Nebula must define its own public `NebulaMetricOperation` enum, gated `@available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)`, and map to/from `OSMetricOperation` at the Nebula↔os boundary inside the module (where `internal` is visible). **Defer to Nebula 27** — the measure surface shipped in Nebula 0.5.0 ([[nebula-standardize-measure]]) does not yet expose metric operations, so there is no present pressure to ship the mirror enum.
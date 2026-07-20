---
tags: [padroes, architecture, data, persistence, network, swiftdata, userdefaults, remote, nebula]
aliases: [Nebula data layer, Nebula network layer, SwiftData in Nebula, Nebula persistence, NebulaHTTPGateway, data-network plan]
related: [[nebula-clean-architecture-toolkit]], [[nebula-meridian-router]], [[nebula-presentation-architecture]], [[nebula-repository]], [[nebula-errors]], [[data-network-open-questions]]
status: researched
researched: "2026-07-19"
---

# Data + Network architecture — research & plan (pre-implementation)

The next major surface after the presentation layer ([[nebula-presentation-architecture]]): **data (SwiftData, UserDefaults) + network (remote)**. This note captures the verified ground truth and the architectural frame; the open owner decisions live in [[data-network-open-questions]]. Source of truth = root docs; this is synthesis. **SwiftData facts below are verified by a `swiftc -typecheck` probe against the Xcode 27 Beta 3 `MacOSX27.0.sdk` (target `arm64-apple-macos26.0`), NOT WebFetch** (which hallucinates availability — see [[ci-warning-masking-and-inference-fragility]] / risk #126).

## Verified SwiftData facts (typecheck probe, 2026-07-19)

Probe: `$CLAUDE_JOB_DIR/tmp/swiftdata_probe.swift` — `@Model final class Item`, `expectSendable<T: Sendable>` witnesses, `-typecheck`. Results:

| Symbol | Sendable? | Evidence |
|---|---|---|
| `ModelContainer` | **Yes** ✅ | `expectSendable(container)` typechecks clean. Holdable in a Nebula-side config/struct. |
| `ModelContext` | **No** ❌ | `extension ModelContext: @unchecked Sendable` is gated `@available(*, unavailable, message: "contexts cannot be shared across concurrency contexts")`. Must be confined to one actor. |
| `@Model` class (`Item`) | **No** ❌ | The `@Model` macro emits `extension Item: Sendable` gated `@available(*, unavailable, message: "PersistentModels are not Sendable, consider utilizing a ModelActor or use Item's persistentModelID instead")`. |
| `FetchDescriptor<Item>` | **Yes** ✅ | Typechecks clean. Build anywhere, send into the actor. |
| `PersistentIdentifier` | **Yes** ✅ (by design) | The Sendable identity you pass across actors instead of the `@Model` instance. |
| Availability floor | **Below `.v26`** ✅ | Probe compiled clean against `arm64-apple-macos26.0` with no `@available` errors → SwiftData is iOS 17 / macOS 14 (below the Nebula 26 floor, ungated). |

**Implication — SwiftData's concurrency model is `@ModelActor`.** A `@ModelActor`-backed repository owns the `ModelContext` off the main actor; you pass `PersistentIdentifier` (Sendable) or DTOs across boundaries, never `@Model` instances. This maps **exactly** onto Nebula's async-port pattern (the Meridian precedent, [[nebula-meridian-router]]): a `@ModelActor` is the concrete adapter; the async `NebulaRepository` port is the seam.

## How SwiftData fits the existing Wave H ports (no new Nebula port needed)

The repository ports shipped in Wave H ([[nebula-repository]]) are already the right shape:

- `NebulaRepository<Element>: Sendable` with `associatedtype Element: Sendable`.
- `NebulaReadOnlyRepository` — `func count() async throws -> Int`, `func all() async throws -> [Element]`, …
- `NebulaKeyedRepository` — `func find(id: Element.ID) async throws -> Element?` (where `Element: NebulaEntity`).
- `NebulaWritableRepository` — `func save(_ entity: Element) async throws`.
- `NebulaDeletableRepository` — `func delete(_ id: Element.ID) async throws`.

All `async throws`, `Element: Sendable`. A SwiftData `@ModelActor` adapter conforms directly: `Element` is the **Sendable domain entity/DTO** (NOT the `@Model` class — it's not Sendable); the adapter maps `@Model` ↔ `Element` internally and passes `PersistentIdentifier` across the actor hop. This is the Clean Architecture intent anyway (the `@Model` is a persistence detail, the domain entity is a Sendable value). **Conclusion: Nebula ships NO new port for SwiftData.** The only question is *where the adapter lives* — a binding-rule placement decision (see [[data-network-open-questions]] Q1).

## Network (remote) — in Nebula's scope, no binding-rule tension

`URLSession` is Foundation. The `NebulaGateway` scaffold ([[nebula-repository]]) already carries the contract: `NebulaGatewayConfiguration` holds `endpoint`/`headers`/`decoder`/`encoder` (reusing `NebulaJSONDecoder`/`NebulaJSONEncoder`)/`logger`/`timeout`/`handler`; `NebulaGateway: Sendable` is the bare marker; `NebulaGatewayConfig` is the process-wide accessor. The deferred slot is the concrete `NebulaHTTPGateway` — Foundation-only, mirrors `NebulaJSONDecoder`/`Encoder` patterns, bridges `URLError`→`NebulaError`. **No new framework import → ships in Nebula.**

A `NebulaRetryPolicy`/`NebulaRetry` (Sendable value, exponential backoff + jitter, a predicate of retentable `URLError` codes, honoring cancellation) is the natural companion — and it's the piece the owner flagged ("retry de api error" → a clean, testable retry primitive belongs in the toolkit).

## UserDefaults — Foundation, with a Sendable wrinkle

`UserDefaults` is Foundation (below floor, ungated) — but it is a reference type and **not** `Sendable` by declaration (documented thread-safe, not compiler-proven). Per the binding rule (no `@unchecked Sendable` on Nebula-defined types; region-based isolation / `Mutex` before `@unchecked`), a Nebula Sendable wrapper holds it in a `let Mutex<UserDefaults>` and serializes access — giving a `NebulaDefaults`/`NebulaPreferences` Sendable façade with no `@unchecked`. This is Foundation-only → ships in Nebula (an ergonomics + a preferences port). Cosmos has no persistence precedent (verified — only `CosmosAsyncImage.swift` touches networking).

## Binding-rule frame (the deciding axis)

Nebula allows only `Foundation` + `os` + `Synchronization` + `_Concurrency` + `CryptoKit` (gated behind `NebulaHashAlgorithm`). Per surface:

| Surface | Framework | Binding-rule tension? | Likely home |
|---|---|---|---|
| Network (`NebulaHTTPGateway` + `NebulaRetry`) | `URLSession` (Foundation) | None | **Nebula** (0.4.x) |
| UserDefaults (`NebulaDefaults`) | `UserDefaults` (Foundation) | None (wrap in `Mutex`) | **Nebula** (0.4.x) |
| SwiftData (`@ModelActor` adapter) | `SwiftData` (a 6th framework) | **Yes** — new framework import | **Owner decision** — app adapter (a) / sibling package (c, mirror Meridian) |

The SwiftData decision is the Q4 of this cycle (see [[data-network-open-questions]] Q1).

## Recommended waves (plan — pending owner decision on Q1)

- **Wave N1 — Network (remote)** — `NebulaHTTPGateway` (Foundation, over the existing `NebulaGateway` scaffold) + `NebulaRetryPolicy`/`NebulaRetry` (Sendable, backoff+jitter, retentable-error predicate, cancellation-aware) + `URLError`→`NebulaError` bridge. Tests. Vault + DocC. **In Nebula.**
- **Wave N2 — UserDefaults** — `NebulaDefaults`/`NebulaPreferences` Sendable façade (`let Mutex<UserDefaults>`, no `@unchecked`) + a preferences port. Tests. **In Nebula.**
- **Wave N3 — SwiftData** — depends on Q1. If (c) sibling package: a new package (working name "Aurora") depending on Nebula, owning the `@ModelActor`-backed repository adapter + `@Model`↔DTO mapping + `ModelContainer` wiring + async port (mirror Meridian). If (a) app-owned: ship nothing in Nebula, document the pattern in a vault note + an example.
- **Wave N4 — Governance + final gate** — ADR (`DECISIONS.md`), `VERSIONING.md` (if a new package), `ARCHITECTURE.md` (Data + Network section), `ROADMAP.md`, vault finalize, DocC, per-platform gate, tag `0.4.0`.

Same cycle as the presentation work: research → vault → waves with a code review at the end of each.

## Notes / guardrails

- SwiftData is a **binary `.swiftmodule`** (no textual `.swiftinterface`), like `_Concurrency` Clock (risk #123) — availability/Sendable facts come from a `swiftc -typecheck` probe + the macro-expansion notes the compiler emits, NOT a local grep. The probe above is the authority for the Sendable table.
- `ModelContext` on the main actor is allowed (the common SwiftUI pattern) but the `@ModelActor` off-main form is what composes with Nebula's `@MainActor`-free stance — same async-port reasoning as the Meridian `Router`.
- `Element: Sendable` on the repository ports is load-bearing: it forces the SwiftData adapter to map to a Sendable domain entity, not leak `@Model` across the port. This is a feature, not a friction.
- Retry must honor `Cancellation` (the deferred `NebulaCancellation` from Wave H, decision #13) — so N1 may pull `NebulaCancellation`/`NebulaError.wrapAsync` forward, or N1 ships retry with a minimal cancellation check and the full `NebulaCancellation` lands in its own wave.
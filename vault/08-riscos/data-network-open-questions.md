---
tags: [riscos, architecture, data, network, decisions, swiftdata, nebula]
aliases: [data network open questions, SwiftData placement, NebulaHTTPGateway decisions, Aurora decisions]
related: [[nebula-data-network-architecture]], [[nebula-clean-architecture-toolkit]], [[nebula-meridian-router]], [[presentation-architecture-open-questions]]
status: decided
researched: "2026-07-19"
decided: "2026-07-19 (Q1 = (c) Aurora sibling package — owner delegation 'o que achar melhor')"
---

# Data + Network — Open Questions (owner decisions)

The research ([[nebula-data-network-architecture]]) converges on a strong recommendation but leaves **owner-level decisions** before implementation. Verified facts (SwiftData Sendable table, repository-port shape, Gateway scaffold) are in that note; this is the decision list.

## Q1. Where does SwiftData live? — app adapter (a) vs sibling package (c)

**Recommendation: option (c), a new sibling package (working name "Aurora") — IF the ecosystem is meant to be a complete architecture toolkit.** This is the Q4 of this cycle ([[presentation-architecture-open-questions]] Q4 decided (d) Meridian).
- Only option that **compiler-enforces** the Clean Architecture dependency rule across packages for persistence: `import Aurora` from Nebula is a hard compile error (Nebula `dependencies: []`; SR-1393 doesn't cross package boundaries). Mirrors Meridian exactly. Aurora owns the `@ModelActor`-backed repository adapter + `@Model`↔DTO mapping + `ModelContainer` wiring; Nebula ships only the async `NebulaRepository` ports (already shipped in Wave H — no new port needed).
- **Fallback — option (a)**: ship nothing SwiftData-specific in Nebula; the app implements `NebulaRepository` with its own `@ModelActor` adapter. Honest, honors "concrete adapters live in the app" (Wave H default); leaves the persistence story incomplete for an architecture library. Natural if the third-package maintenance budget isn't available now.
- **Rejected**: (b) a gated Nebula helper importing `SwiftData` behind a name (CryptoKit-style) — SwiftData is heavyweight, `ModelContext`/`@Model` are not Sendable (verified), and the `@ModelActor` form wants its own module graph; grafting it into Foundation-only Nebula re-creates the Meridian tension that option (d) already resolved by splitting packages.
- **The real trade-off** (same as Q4): maintenance budget for a third package vs. completeness of the architecture story. Complete toolkit → (c). Toolkit-of-seams + app owns the persistence adapter → (a).

## Q2. Package naming (if Q1 = c)

**Recommendation: "Aurora"** (working name) — evokes dawn/storage/persistence, distinct from Nebula/Cosmos/Meridian, no namespace clash. Alternatives: `NebulaData`, `NebulaStore`, `NebulaPersistence`, `CosmosData`. `NebulaData` is misleading (Nebula is Foundation-only; this would muddy the brand — same reasoning that rejected `NebulaUI` for Meridian). Decide alongside Q1.

## Q3. Version coordination (if Q1 = c)

**Recommendation: Aurora N ↔ Nebula N ↔ OS N** (mirror the Meridian N ↔ Nebula N ↔ OS N policy, [[nebula-meridian-router]]). Aurora depends on Nebula at the same major; a Nebula major bump lets an Aurora major bump. Within a major: semver minor/patch. Policy in `VERSIONING.md` extended; changes in `CHANGELOG.md`. Decide alongside Q1.

## Q4. Network scope — just HTTP, or a broader remote client?

**Recommendation: ship `NebulaHTTPGateway` + `NebulaRetryPolicy`/`NebulaRetry` for v0.4; defer WebSocket / SSE / a higher-level "remote API client" until a second use earns them.** The `NebulaGateway` scaffold is HTTP-shaped (endpoint/headers/timeout); a clean URLSession gateway + a testable retry primitive is the high-payoff core. `URLSessionWebSocketTask` / `URLSessionStreamTask` are Foundation too, but they're a different shape — defer to avoid speculative surface.

## Q5. Retry semantics — and does it pull `NebulaCancellation` forward?

**Recommendation: `NebulaRetryPolicy` as a Sendable value (max attempts, base delay, multiplier, max delay, jitter, a `@Sendable (URLError) -> Bool` retentable predicate) + `NebulaRetry`/`withRetry(_:operation:)` over `async throws`.** Exponential backoff + full jitter. Honor cancellation: if the operation observes `Task.isCancelled`, stop retrying and surface `CancellationError`→`NebulaError`. **Open**: ship a minimal cancellation check in N1 and defer the full `NebulaCancellation`/`NebulaError.wrapAsync` (Wave H decision #13) to its own wave, OR pull `NebulaCancellation` forward as N1's companion. Lean: minimal check now, full `NebulaCancellation` later — keeps N1 scoped.

## Q6. UserDefaults surface — façade only, or a preferences port too?

**Recommendation: both, minimal.** A `NebulaDefaults`/`NebulaPreferences` Sendable façade (`let Mutex<UserDefaults>`, typed get/set over `Codable`/`RawRepresentable`/primitives, no `@unchecked`) **plus** a thin `NebulaPreferences` port in `Architecture/` so an app can swap UserDefaults for a test double / iCloud key-value store / encrypted store. The façade is the Foundation ergonomics; the port is the architecture seam. Keep the v0.4 surface lean — no key-namespace policy, no change observation yet.

## Decision status

**DECIDED (2026-07-19) — Q1 = (c) sibling package "Aurora"** (owner delegation: "o que achar melhor"; consistent with the Meridian (d) precedent — complete-toolkit path). Q2 → "Aurora" (kept the working name). Q3 → Aurora N ↔ Nebula N ↔ OS N lockstep (mirror Meridian). Q4 → `NebulaHTTPGateway` + `NebulaRetry` now, WS/SSE deferred. Q5 → `NebulaRetryPolicy` Sendable value + `withRetry(_:operation:)`, full jitter, minimal cancellation check now (full `NebulaCancellation` deferred). Q6 → both UserDefaults façade + port.

Implementation follows the wave pattern N1→N4 with build gates (see [[nebula-data-network-architecture]] § Recommended waves): **N1 Network** (`NebulaHTTPGateway` + `NebulaRetryPolicy`/`NebulaRetry`, in Nebula) → **N2 UserDefaults** (`NebulaDefaults` façade + port, in Nebula) → **N3 SwiftData** (Aurora sibling package, `@ModelActor` adapter) → **N4 governance + final gate + tag `0.4.0`**. The ADR is appended to `DECISIONS.md` at N4 (mirroring the Wave H / presentation ADR rows).

**Progress: N1 ✅ shipped** ([[nebula-network-retry]], 557 tests). **N2 ✅ shipped** ([[nebula-preferences]], 574 tests — `NebulaPreferences` port + `NebulaDefaults` `Mutex<UserDefaults>` façade, `sending` init, no `@unchecked`). **N3 ✅ shipped** ([[nebula-aurora-swiftdata]], 12 Aurora tests — `AuroraEntityMapping` + `AuroraRepository<Mapping>` `@ModelActor` adapter conforming to all four `NebulaRepository` ports; `import Aurora` from Nebula is a hard compile error). **N4 pending** (governance + tag `0.4.0`).
---
tags: [nebula, architecture, research, roadmap, swift, clean-architecture]
aliases: [nebula app readiness, app readiness research, nebula scope research, Nebula wave plan N9+]
related: [[nebula-clean-architecture-toolkit]], [[nebula-network-endpoint-client]], [[nebula-registry-di]], [[nebula-errors]]
status: researched
researched: "2026-07-19"
---

# Nebula — App-readiness scope research (what else Nebula can do)

> Research sweep (2026-07-19) across the whole Nebula scope, focused on **Apple best practices + patterns**. This note is the canonical hub/synthesis; per-area notes hold the verified API depth. The root docs (`ARCHITECTURE.md`, `DECISIONS.md`, `ROADMAP.md`, `CLAUDE.md`) are the source of truth — root doc wins on conflict. All Apple API claims verified against the Xcode 27 Beta 3 `.swiftinterface` / C headers (NOT WebFetch, which hallucinates availability); unverified items are flagged inline.

Spawned from the gap-analysis after 0.5.0: "pensando na construção de um app, temos clean architecture, tdd, network, data, ui (cosmos). está faltando algo?" → "vamos pensar e pesquisar tudo que podemos fazer nesse escopo do nebula, focando nas melhores práticas e nos padrões da apple." Eight research dimensions ran in parallel; findings below.

## Taxonomy

- **Tier 1 — essencial, Foundation-tier, 5-platform, sem gate** (alta prioridade): Keychain/secure storage, auth interceptor (401 refresh-and-retry), composition root recipe, user-error bridge, environment value, feature flags.
- **Tier 2 — system-framework façades, platform-gated** (importante, feature-dependente): background tasks, notifications, MetricKit observability, network hardening (streaming/multipart/download/pagination).
- **Tier 3 — monetização / sibling** (feature-dependente): StoreKit IAP port, Aurora schema migration.
- **Defer (rastreado):** biometry (`LAContext` é `API_UNAVAILABLE(tvOS)` no nível da classe — carve-out de plataforma, não de escopo), ActivityKit (iPhone-only → sibling), CloudKit (sibling, heavy), unified permissions port (app glue), TipKit (Cosmos), AppIntents (app-owned), legacy `MXMetricManager` (deprecated).

## Master scope-verdict table

| Área | Surface candidata | Veredito | Wave | Notas de binding |
|---|---|---|---|---|
| Keychain | `NebulaKeychain` façade + `NebulaSecureStore` port + `NebulaKeychainConfig` | **Façade + Port + Config** | N9 ✅ shipped 0.6.0 | Reusa o padrão de config do `NebulaDefaults`, MAS `NebulaKeychain` é **stateless `final class` sem Mutex** (C API thread-safe, sem objeto Swift para isolar — `Sendable` derivado, o precedente `NebulaError.Box`); `import Security` confirmed in-bounds (Q resolvido 2026-07-19). Shipped → [[nebula-keychain]] |
| Auth | `NebulaHTTPInterceptor` + chain + `NebulaTokenProvider` + `NebulaAuthInterceptor` (401 refresh) | **Port + Façade** | N10 ✅ shipped 0.7.0 | Primeiro `actor` owned-by-Nebula (single-flight refresh); `NebulaRetry.withPolicy` NÃO muta o request → seam novo. Shipped → [[nebula-auth-interceptor]] |
| Composition root | recipe + DocC + `NebulaCompositionExample` (sibling) | **Doc (Nebula) + Example (sibling)** | N11 ✅ shipped 0.8.0 / N11b follow-up | App/`@MainActor` viewmodel é proibido em Nebula → exemplo fica em sibling (precedente Meridian/Aurora). Shipped (recipe) → [[nebula-composition-root]] |
| User error | `NebulaUserError` value + `RecoveryAction` + `.withUserMessageMap` | **Port + Config** | N12 ✅ shipped 0.9.0 → [[nebula-user-error]] | Só mapeamento, **sem novos `Kind` cases**; `RecoveryURL` NÃO é API pública (refutado) |
| Environment | `NebulaEnvironment` enum + `NebulaEnvironmentConfig` + `fromBundle` | **Port (value)** | N13 ✅ shipped 0.10.0 → [[nebula-environment]] | `Bundle`/`ProcessInfo` SÃO Sendable; `.xcconfig` é app-tier |
| Feature flags | `NebulaFeatureFlags` port + `NebulaLocalFeatureFlags` façade + remote port + composite | **Port + Façade** | N14 ✅ shipped 0.11.0 → [[nebula-feature-flags]] | `dependencies: []` → remote backend é app-supplied; `NebulaDefaults`-backed persistence **deferred** (in-memory only); composite é generic first-non-nil (app wires `local > remote > defaults`); `refresh() async throws` (devia do research) |
| Background tasks | `NebulaBackgroundTask` port+façade | **Port + Façade** | N15b | iOS/tvOS/visionOS only — gate explícito `@available(macOS, unavailable)` + `@available(watchOS, unavailable)` (NÃO `@available(iOS 13, *)`); `#if canImport(BackgroundTasks)` whole-file gate + iOS-27 async `submitTaskRequest(_:)`. **Pending.** |
| Notifications | `NebulaNotifications` port+façade + `NebulaPermissionStatus` value | **Port + Façade + Value** | N15a ✅ shipped 0.12.0 | All-5; subsets tvOS-unavailable via **`#if !os(tvOS)`** (precedent — `@available(unavailable)`/`if #available` both invalid for an already-unavailable SDK symbol); UI presentation = Cosmos. Shipped → [[nebula-notifications]] |
| Observability | `NebulaMetrics` façade (new `MetricManager`) + `NebulaDiagnosticSnapshot` + `NebulaMemoryLogHandler.export()` | **Façade + Value + minor** | N16 | New `MetricManager` é iOS 27 → `#if swift(>=6.4)` + tvOS/watchOS unavailable; SEM legacy `MXMetricManager` (evita `@unchecked` Nebula-authored) |
| Network hardening | SSE/WebSocket/multipart/download/pagination | **Façade** | N17 | `URLSessionWebSocketTask` não-Sendable → `final class`/actor façade; tudo abaixo do floor |
| SSL pinning | `NebulaSSLPinning` SPKI-hash delegate | **Façade** | N17 | `import Security` confirmed in-bounds (Q resolvido); Apple prefere `NSPinnedDomains` no Info.plist, façade Nebula só para per-endpoint pinning |
| StoreKit IAP | `NebulaIAPPort` + `NebulaStoreKitGateway` façade + `NebulaIAPConfig` | **Port + Façade** | N18 | Módulo StoreKit faz `import UIKit` plain (não `@_exported`) → UIKit NÃO re-exportado; data APIs UIKit-free |
| Aurora migration | `ModelContainer` factory + `@ModelActor` migration runner + example | **Ship in Aurora** | A1–A3 | `Migration`/`LightweightMigration` protocols NÃO existem (refutado); custom = `MigrationStage.custom` closures |
| Biometry | `NebulaBiometry` port + LAContext façade | **Defer** | — | `LAContext` é `API_UNAVAILABLE(tvOS)` no nível da classe → não pode ser 5-platform; visionOS UNVERIFIED |
| ActivityKit | `Activity<Attributes>` façade | **Defer (sibling)** | — | iPhone-only (framework ausente em tvOS/watchOS/visionOS device SDKs); `Activity` non-Sendable class |
| CloudKit | `CKSyncEngine`-first façade | **Defer (sibling)** | — | `CK*` majoritariamente non-Sendable/`@unchecked`; `CKSyncEngine` (iOS 17) é o único Sendable limpo; pesado |
| Permissions unificadas | `NebulaPermissions` port | **Defer (app glue)** | — | Sem API Apple unificada; importa 4+ frameworks; só o `NebulaPermissionStatus` value vale hoist |
| TipKit | `Tip`-shaped API | **Cosmos-only** | — | `@_exported import SwiftUI` (L7); `Tip.title/message/image` são `SwiftUICore.Text`/`Image` |
| AppIntents | app conforms `AppIntent` → Nebula use-case port | **App-owned (doc-only)** | — | Core module Foundation-tier, sem SwiftUI; Nebula já tem o port (`NebulaUseCase`) — app conforma |

## Unified wave sequence (proposta — pendente confirmação do owner)

**Tier 1 (Foundation-tier, 5-platform, sem gate):**
- **N9 — Keychain + SecureStore port** → `NebulaSecureStore` (port, 3 byte-level reqs) + `NebulaKeychain` (`final class` Mutex-façade sobre `SecItem*`) + `NebulaKeychainConfig` (`.with*`). Deps: nenhum. **✅ SHIPPED 0.6.0 (2026-07-19)** — refinamento Mutex-free aplicado (stateless `final class` + `let config`); ver [[nebula-keychain]].
- **N10 — Network interceptors + auth (401 refresh-and-retry)** → `NebulaHTTPInterceptor` (port: `adapt`/`retry`) + `NebulaHTTPInterceptorChain` + `NebulaTokenProvider` (port) + `NebulaAuthInterceptor` (concrete, `actor` single-flight refresh, retry-once) + `NebulaHTTPClient.intercepted(by:)`. Deps: N9, N5. **✅ SHIPPED 0.7.0 (2026-07-20)** — primeiro `actor` owned-by-Nebula; ver [[nebula-auth-interceptor]].
- **N11 — Composition root recipe + DocC** → `ArchitectureCompositionRoot.md` + recipe (docs-only). Deps: nenhum. **✅ SHIPPED 0.8.0 (2026-07-20)** — docs-only no Nebula (no new type); runnable `@MainActor @Observable` vertical é **N11b** em sibling (Meridian). Ver [[nebula-composition-root]].
- **N12 — User-error bridge** → `NebulaUserError` + `RecoveryAction` + `NebulaErrorConfiguration.withUserMessageMap`. Deps: toolkit (NebulaFailure/NebulaError). **✅ SHIPPED 0.9.0 (2026-07-20)** — value-mapping (NebulaError → NebulaUserError?), NÃO é `NebulaFailure` (direção oposta); `RecoveryURL` refutado; ver [[nebula-user-error]].
- **N13 — Environment value + reader pattern** → `NebulaEnvironment` + `NebulaEnvironmentConfiguration` + `NebulaEnvironmentConfig` + `fromBundle(_:)`. Deps: nenhum. **✅ SHIPPED 0.10.0 (2026-07-20)** — closed enum + reader (cast `Any → String` antes de cruzar isolamento, safe-fail-to-production, pure function sem `Mutex`) + 5th config struct (`baseURLs`/`overrides`) + `Mutex` accessor (two-path DI); `.xcconfig`/scheme wiring é app-tier (deferred); `ProcessInfo` reader não shipped; ver [[nebula-environment]].
- **N14 — Feature flags port + local impl** → `NebulaFeatureFlags` + `NebulaLocalFeatureFlags` + `NebulaRemoteFeatureFlags` + composite. Deps: N2 (NebulaDefaults). **✅ SHIPPED 0.11.0 (2026-07-20)** — `NebulaFlagValue` Sendable enum (bool/string/int/double/json), one-requirement port + typed default-extension bridges (per-call `JSONDecoder`), `NebulaLocalFeatureFlags` `final class` `Mutex` (no `sending` — Dict is Sendable, no `@unchecked`), `NebulaRemoteFeatureFlags` adds `refresh() async throws`, `NebulaCompositeFeatureFlags` Sendable struct first-non-nil + `withSource`; **no process-wide accessor** (constructed-and-passed); `NebulaDefaults`-backed persistence **deferred**; ver [[nebula-feature-flags]].

**Tier 2 (system-framework façades, platform-gated):**
- **N15a ✅ SHIPPED 0.12.0 (2026-07-20) — Notifications + permission status** → `NebulaNotificationCenter` port + `NebulaUNNotificationCenter` `final class : NSObject` delegate-adapter façade + `NebulaNotificationsConfiguration` (6th config) + value types + `NebulaNotificationsError` + `NebulaPermissionStatus` value. **Establishes the `#if !os(<platform>)` precedent** for SDK symbols `API_UNAVAILABLE` (deviates from this note's original `@available(tvOS 26, unavailable)` / `if #available` — both empirically invalid). Ver [[nebula-notifications]].
- **N15b — Background tasks** → `NebulaBackgroundTask` (iOS/tvOS/visionOS, `#if canImport(BackgroundTasks)` whole-file gate + iOS-27 async `submitTaskRequest(_:)`). Deps: nenhum. **Pending.**
- **N16 — MetricKit observability** → `NebulaMetrics` (new `MetricManager`, iOS 27 `#if swift(>=6.4)`, tvOS/watchOS unavailable) + `NebulaDiagnosticSnapshot` + `NebulaMemoryLogHandler.export()` (all-5, tiny). Deps: nenhum.
- **N17 — Network hardening** → `NebulaSSEEventStream` + `NebulaWebSocket` façade + `NebulaMultipartBuilder` + `NebulaDownload` + `NebulaPagedSequence` + `NebulaSSLPinning` (SPKI-hash delegate, `import Security`). Deps: N5, N10.

**Tier 3 (monetização / sibling):**
- **N18 — StoreKit IAP port** → `NebulaIAPPort` + `NebulaStoreKitGateway` + `NebulaIAPConfig`. Deps: toolkit.
- **A1–A3 — Aurora schema migration** (sibling) → `ModelContainer` factory + `@ModelActor` migration runner + example. Deps: Aurora N3.

## Decisão do owner (resolvida 2026-07-19)

**Q — "Foundation-only" significa estritamente a lista do `CLAUDE.md`, OU qualquer framework de sistema Apple não-UI?**

- **RESOLVIDO: adotar o princípio "non-UI Apple system framework".** Security / BackgroundTasks / UserNotifications / MetricKit / StoreKit são admissíveis no escopo Nebula, com gates de plataforma apropriados (consistente com o precedente Network.framework já shipped em 0.5.0). Próxima wave: **N9 (Keychain + secure store)**.
- `CLAUDE.md` foi atualizado para enumerar os frameworks de sistema permitidos (Foundation + `os` + `Synchronization` + `_Concurrency` + `CryptoKit` atrás de `NebulaHashAlgorithm` + `Network` + `Security` + `BackgroundTasks` + `UserNotifications` + `MetricKit` + `StoreKit`), com a regra: **somente frameworks de sistema não-UI, nunca UIKit/SwiftUI/SwiftData**, e gates `@available` por-platform obrigatórios. ADR em `DECISIONS.md`.
- **Impacto:** todas as waves Tier 1–3 (N9–N18 + A1–A3) são viáveis. SSL pinning (N17) sai do "pendente" — `import Security` confirmed in-bounds. biometry permanece Defer (`LAContext` é `API_UNAVAILABLE(tvOS)` no nível da classe — não é questão de escopo, é de plataforma).

## Correções / specs refutadas (não citar como fato)

- **`RecoveryURL` NÃO é API pública Apple** — só o símbolo privado `_PKErrorRecoveryURLKey` em `PassKit.tbd`/`FinanceKit.tbd`. O gap-analysis original estava errado; a ponte user-error usa `RecoverableError` + `recoveryAttempterErrorKey`, não `RecoveryURL`. (→ [[nebula-usererror-environment-featureflags]])
- **`Migration` / `LightweightMigration` protocols NÃO existem** no `SwiftData.swiftinterface` (Xcode 27 Beta 3). Custom migration é **exclusivamente** `MigrationStage.custom` closures (`@Sendable (ModelContext) throws -> Void`, `@preconcurrency`). (→ [[nebula-aurora-migration]])
- **`NebulaRetry.withPolicy` NÃO muta o request entre tentativas** (`NebulaRetry.swift:170-172`) — o predicado `isRetriable` só decide retry/não-retry. 401-refresh-and-retry precisa de um **novo seam interceptor** (motiva N10). (→ [[nebula-keychain-auth]], [[nebula-network-hardening]])
- **MetricKit tem DUAS gerações**: legacy `MXMetricManager` (Obj-C, deprecated "Use MetricManager instead", `API_UNAVAILABLE(tvos, watchos)`, não-Sendable) e new `MetricManager` (Swift-first, iOS 27, `@unchecked Sendable` authored-by-Apple, reports `Sendable+Codable`). Nebula deve envolver **só o novo** (evita author `@unchecked` em tipo Nebula). (→ [[nebula-metrickit-observability]])
- **`LAContext` é `API_UNAVAILABLE(tvOS)` no nível da classe** → biometry não pode ser tipo 5-platform. visionOS UNVERIFIED. (→ [[nebula-keychain-auth]])
- **StoreKit module faz plain `import UIKit`/`import AppKit` (não `@_exported`)** → UIKit NÃO re-exportado para o namespace Nebula; data APIs são UIKit-free → port StoreKit é viável. (→ [[nebula-storekit-engagement]])
- **`BGTaskScheduler` é iOS/tvOS/visionOS** (macOS+watchOS unavailable); `submit(_:)` deprecated iOS 27 → novo `submitTaskRequest(_:)` async. Gate deve ser explícito per-platform unavailable, **NÃO `@available(iOS 13, *)`** (o `*` fallback habilita todos). (→ [[nebula-background-notifications]])
- **Nomes de API corrigidos** (agent 8): `ActivityKitAuthorizationInfo`→`ActivityAuthorizationInfo`; `database(withPublicScope:)`→`database(withDatabaseScope:)`; `Tips.DisplayRule`→`Tips.Rule`; `Tips.Group`→`TipGroup`; `Tips.reloadData()`→`resetDatastore()`; `Activity.dismiss()` não existe (use `end(..., dismissalPolicy:)`); `Activity.activityHandleUpdates`→`activityUpdates`; `AppIntentResult`/`SnippetGroup` não existem (use `IntentResult`/`SnippetIntent`).
- **`Bundle` e `ProcessInfo` SÃO Sendable** (compile-verified Swift 6); `UserDefaults` NÃO (`@_nonSendable(_assumed)`). `infoDictionary` retorna `[String: Any]` — os `Any` NÃO são Sendable → cast para `String`/`Bool`/`Int` antes de cruzar isolamento. (→ [[nebula-usererror-environment-featureflags]])

## Per-area notes

- [[nebula-keychain-auth]] — Keychain (Security C API) + LocalAuthentication + auth/session + 401 refresh-and-retry interceptor.
- [[nebula-aurora-migration]] — SwiftData `VersionedSchema`/`SchemaMigrationPlan`/`MigrationStage` + `ModelContainer` factory + `@ModelActor` migration runner.
- [[nebula-composition-root]] — app composition root / DI wiring in Swift 6 (no SwiftUI Environment, no third-party DI).
- [[nebula-metrickit-observability]] — MetricKit two generations + iOS log-export reality + crash diagnostics.
- [[nebula-background-notifications]] — `BGTaskScheduler` + `UNUserNotificationCenter` + permissions (no unified Apple API).
- [[nebula-network-hardening]] — SSL pinning + interceptors + SSE/WebSocket + multipart + download + pagination.
- [[nebula-usererror-environment-featureflags]] — `LocalizedError`/`RecoverableError` + environment + feature flags.
- [[nebula-storekit-engagement]] — StoreKit 2 / TipKit / AppIntents / ActivityKit / CloudKit scope verdicts.

Related (já existentes): [[nebula-clean-architecture-toolkit]] (seams que estas waves estendem), [[nebula-network-endpoint-client]] (N5–N8, base de N10/N17), [[nebula-registry-di]] (DI sem container — base do composition root), [[nebula-errors]] (envelope que N12 estende), [[nebula-preferences]] (padrão Mutex-façade que N9 espelha), [[nebula-aurora-swiftdata]] (base de A1–A3).
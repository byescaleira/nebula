---
tags: [nebula, architecture, background-tasks, backgroundtasks, swift, concurrency, sendable, gating]
aliases: [nebula background tasks, NebulaBackgroundTask, NebulaBackgroundTaskScheduler, NebulaBGTaskScheduler, NebulaBGTaskBox, NebulaBackgroundTaskConfiguration, nebula background tasks mac watch gate]
related: [[nebula-notifications]], [[nebula-background-notifications]], [[nebula-keychain]], [[nebula-clean-architecture-toolkit]], [[nebula-swift6-concurrency]]
status: shipped
shipped: "0.13.0 (Wave N15b, 2026-07-20)"
---

# Nebula — Background tasks (shipped)

> Shipped note for the background-tasks dimension of [[nebula-app-readiness-research]] (wave N15b, the higher-risk half of the N15 split — N15a notifications [[nebula-notifications]] is the sibling). Source of truth: `Sources/Nebula/Architecture/BackgroundTasks/` (7 files). Parent research: [[nebula-background-notifications]].

## O que shipou (Nebula 0.13.0)

- **`NebulaBackgroundTaskKind`** — `Sendable`/`Equatable`/`Hashable`/`CaseIterable`/`CustomStringConvertible` enum, `.appRefresh` (`BGAppRefreshTask`) / `.processing` (`BGProcessingTask`). All-5, sem gate (é um value Nebula, não o SDK type).
- **`NebulaBackgroundTaskRequest`** — `Sendable`/`Equatable`/`Hashable` struct: `identifier`/`kind`/`earliestBeginDate`/`requiresNetworkConnectivity`/`requiresExternalPower` (os dois últimos são processing-only, ignorados para `.appRefresh`). Sendable derived.
- **`NebulaBackgroundTask`** — o **Sendable launch-time handle**: `Sendable`/`Equatable` (equality por `identifier`+`kind` — as closures `@Sendable` não são comparáveis). Guarda `identifier`/`kind` + dois closures `@Sendable` (`finish: (Bool) -> Void`, `setExpiration: (@escaping @Sendable () -> Void) -> Void`) que **capturam apenas o façade Sendable + identifier** (NUNCA o `BGTask`) e chamam `façade.finishTask`/`façade.setExpiration`. Métodos públicos `complete(success:)`/`onExpiration(_:)`. Sendable derived. O `@escaping` interno no param de `setExpiration` é **necessário explícito** — Swift 6 não infere `@escaping` para o param de uma closure `@Sendable` armazenada.
- **`NebulaBackgroundTaskScheduler`** — port `Sendable` com 5 requirements (`register(_:) async -> Bool`, `submit(_:) async throws`, `cancel(_:) async`, `cancelAll() async`, `pendingRequests() async -> [NebulaBackgroundTaskRequest]`). O launch handler **não** está no port — vive no config.
- **`NebulaBGTaskScheduler`** — `final class : NebulaBackgroundTaskScheduler, Sendable` (sem `NSObject` — não há protocol `@objc` aqui, ao contrário de `NebulaUNNotificationCenter`). `let config` + `let liveTasks: Mutex<[String: NebulaBGTaskBox]>`. `register`/`submit`/`cancel`/`cancelAll`/`pendingRequests`; `bridgeLaunch` envolve o `BGTask` na box, armazena, builda o handle, chama `config.launch`.
- **`NebulaBackgroundTaskConfiguration`** — 7º config, `Sendable` (NÃO `Equatable`), `launch: @Sendable (NebulaBackgroundTask) -> Void` (default `{ _ in }` capture-free no-op), `.withLaunch` retorna tipo concreto, `static let default`. `NebulaBackgroundTaskConfig` = caseless `enum` + `Mutex<NebulaBackgroundTaskConfiguration>(.default)` + `get()`/`set(_:)`.
- **`NebulaBackgroundTaskError`** — open-struct (`NebulaFailure, Equatable, Hashable`) + nested `Kind` (presets `notPermitted`/`schedulingFailed`/`tooManyPending`/`unavailable`/`immediateRunIneligible`/`unknown` — mirror `BGTaskSchedulerErrorCode`) + `coarseKind` (`schedulingFailed → .cocoa`, resto `→ .unknown`) + `toNebulaError(kind:)` (**sem novos `NebulaError.Kind` cases**). Factory statics com `underlying: NebulaError.Box?` para preservar o SDK `NSError` em todo path de mapeamento. Precedente [[nebula-keychain]].

## Precedente estabelecido: `@available(<platform>, unavailable)` declaration gate (e a 4-form gating taxonomy)

**Esta é a contribuição arquitetural-chave do N15b — e uma correção empírica do plano/research.** O research ([[nebula-background-notifications]]) e o plano diziam que N15b estabeleceria o gate `#if canImport(BackgroundTasks)` whole-file. **Empiricamente ERRADO**, verificado via `swiftc -emit-module` contra as 5 SDKs:

- `BackgroundTasks.framework` está **fisicamente presente nas 5 SDKs** (headers + `.tbd` em macOS/watchOS também). Logo `#if canImport(BackgroundTasks)` é `true` em macOS/watchOS — **gatea nada**. A referência subsequente a `BGTaskScheduler.shared` então falha: `'BGTaskScheduler' is unavailable in macOS/watchOS` (a classe é `API_UNAVAILABLE(macos) API_UNAVAILABLE(watchos)`).
- `@available(macOS 26, unavailable)` é **sintaxe inválida** — "unavailable can't be combined with shorthand 'macOS 26'". `unavailable` não leva versão. A forma válida é `@available(macOS, unavailable)` (sem versão).

A forma compile-safe é **type-level `@available(macOS, unavailable) @available(watchOS, unavailable)` declaration** no façade Nebula (precedente `NebulaLogStoreExporter`): declarar um **símbolo Nebula** unavailable **suprime o type-checking do body** em macOS/watchOS, então a referência unavailable a `BGTaskScheduler.shared` lá dentro não é validada nessas platforms. O type ainda **existe** nas 5 plataformas (pode ser nomeado em assinaturas shared) — é meramente unavailable em macOS/watchOS. Isto é o **complemento** do `#if !os(<platform>)` de N15a (que exclui um **SDK symbol** `API_UNAVAILABLE` de um build quando um declaration gate não se aplica — ex. um override de requirement de protocolo já-unavailable).

### A 4-form gating taxonomy (consolidada N15a + N15b)

1. **`@available(<platform>, unavailable)`** — declaration gate; declara um **símbolo Nebula-authored** unavailable numa platform. ← **N15b façade usa isto** (precedente `NebulaLogStoreExporter`).
2. **`#if !os(<platform>)`** — compile gate; exclui um **SDK symbol `API_UNAVAILABLE`** de um platform build (quando um declaration gate não se aplica — ex. override de requirement já-unavailable). ← N15a precedente.
3. **`#if canImport(<framework>)`** — whole-file gate para um **framework genuinamente ausente** (não presente no SDK da platform de forma alguma). ← **NÃO se aplica** a `BackgroundTasks` (presente-mas-unavailable em mac/watch); reservado para um futuro framework realmente ausente.
4. **`#if swift(>=6.4)` + `if #available(<platform> N, *)`** — OS-27-only SDK symbols (acima do floor `.v26` do Nebula). ← N15b `submit` async path usa isto.

## A Sendability — `@unchecked` reference-type box `NebulaBGTaskBox` (correção do plano)

**A parte dura, resolvida empiricamente (correção do plano N15b).** O plano dizia: `Mutex<[String: BGTask]>` live-task map, Sendable derived, **sem `@unchecked`** (precedente `NebulaDefaults` `Mutex<non-Sendable>`). **Empiricamente IMPOSSÍVEL** — verificado via `swiftc -emit-module` whole-module macOS/iOS Swift 6:

- `BGTask` é non-`Sendable` e system-delivered **dentro** do launch callback `@Sendable`. Armazená-lo diretamente num `Mutex<[String: BGTask]>` via `liveTasks.withLock { $0[id] = task }` falha whole-module com **`'inout sending' parameter '$0' cannot be task-isolated at end of function`** — uma **region-isolation wall**: um class non-`Sendable` que chega como **param de closure** não pode ser `sending`-transferido para uma region `Mutex` que o compilador não consegue provar exclusiva. O precedente `NebulaDefaults` `Mutex<non-Sendable>` **NÃO se aplica** — `UserDefaults.standard` chega num **`sending` API boundary pública** que o caller assertiona; `BGTask` chega numa closure onde a exclusividade é improvável.
- Todas as variantes testadas e falharam: `Mutex<[String: BGTask]>` withLock, per-task `Mutex<BGTask?>` via `SendableBox` `final class` + init `Mutex(task)`, `sending` closure param, `sending` method-param helper, launchHandler não-`@Sendable`. A wall é a transferência `sending` do class system-delivered, **independente** de o holder ser `@unchecked` ou derived-Sendable.

**Resolução** — um `final class @unchecked Sendable` `NebulaBGTaskBox` reference-type wrapper guardando o `BGTask` como **plain `let`** (sem Mutex, sem init `sending` — o plain stored-property init compila). Isto é o **precedente `NebulaMemoryLogHandler`** ("the only `@unchecked` type … justified by the lock and safe because it is a reference type, not a Nebula-defined value type"). A binding proíbe `@unchecked` em **value types**; um reference type atrás de um boundary `@unchecked` auditado (uma vez atribuído, imutável, system-owned) é a exceção permitida. A box cruza isolation; o façade então guarda `Mutex<[String: NebulaBGTaskBox]>` (boxes Sendable → dict Sendable → `Mutex` Sendable) e a conformance `Sendable` do façade é **derived** — **sem `@unchecked` no façade**. O `@unchecked` fica isolado na única box reference-type; o façade e o handle ambos derived `Sendable`.

- Thread-safety: a box é buildada uma vez por launch, o `let task` nunca é reassigned, e o façade serializa acesso per-identifier via seu `Mutex` (um `finishTask`/`setExpiration` por identifier por vez). `BGTask.setTaskCompleted(success:)` / `expirationHandler` são os entry points documentados do system, chamados uma vez por task.
- `BGTaskScheduler.shared` é fetched localmente por call, nunca stored (o singleton shared não pode ser `sending`-consumed — mesma lição que `.current()` em [[nebula-notifications]]).

## `submit`: dual-path, warning-clean sob `.v26`

- **iOS-27 async** — `BGTaskScheduler.shared.submitTaskRequest(_:) async throws` (OS-27 symbol) gateado `#if swift(>=6.4)` (ausente do SDK Xcode 26.4 / Swift 6.3) + runtime `if #available(iOS 27, tvOS 27, visionOS 27, *)`.
- **iOS-26 fallback** — o deprecated sync `BGTaskScheduler.shared.submit(_:)` (`submitTaskRequest:error:`, deprecated iOS 27). **Deprecation warnings disparam só quando o deployment target ≥ a versão obsoleted (`27 > 26`)**, então sob `.v26` o fallback é **warning-clean** (probe-confirmed RC=0) e mantém a capability headline do façade usável no próprio floor do Nebula. Se o floor subir para iOS 27, o deprecated path warnaria — documentado; o async path passa a ser o único.
- Um método, ambos paths, zero warnings sob `.v26`.

## Restrição de testabilidade (maior que N15a)

Todo SDK type de `BackgroundTasks` (`BGTaskScheduler`, `BGTask`, `BGAppRefreshTaskRequest`, `BGProcessingTaskRequest`) é `API_UNAVAILABLE(macos)`. `swift test` roda no **macOS host**, onde nenhum compila. Então:

- Value types / handle / config / port / error (all-5, sem BG types) → testados em macOS.
- Façade + mapping helpers → gateados `#if !os(macOS) && !os(watchOS)`; **compilam** em iOS/tvOS/visionOS (xcodebuild-verified) mas são **dead code** no macOS test host. Nenhum round-trip executa em `swift test`.
- `BGTaskScheduler.shared` é non-functional num headless test bundle (sem app context — a lição `UNUserNotificationCenter.current()` em [[nebula-notifications]]). O façade é **nunca instantiated** em testes; a port seam (`FakeBackgroundTaskScheduler`) + o type-level conformance check + o mapping round-trip provam a architecture. O integration register/submit/cancel é uma limitação documentada (compile-verified em iOS/tvOS/visionOS via `xcodebuild`).

## Verificação (2026-07-20)

`rm -rf .build && swift build` verde, **zero concurrency warnings**. 811 tests / 170 suites. `swift build -c release` verde. `xcodebuild build` BUILD SUCCEEDED nas 5 platforms (iOS/macOS/tvOS/watchOS/visionOS). `xcodebuild docbuild` BUILD DOCUMENTATION SUCCEEDED, zero warnings (`ArchitectureBackgroundTasks.md` resolve; `Nebula.md` config list "Seven" resolve; symbol links resolvem). Anti-patterns ausentes: exatamente um `@unchecked Sendable` (a box); nenhum `#if canImport(BackgroundTasks)` gate; nenhum `@available(macOS 26, unavailable)` usage; nenhum `BGContinuedProcessingTask`/`supportedResources`/`SubmissionStrategy` code; nenhum novo `NebulaError.Kind` case.

## Deferido (rastreado)

- **N15c — `BGContinuedProcessingTask`** (iOS-26-only, `API_UNAVAILABLE(macos, tvos, visionos, macCatalyst, watchos)`): request subclass + `SubmissionStrategy` + `Resources` + `supportedResources` + `NSProgressReporting` + title/subtitle. Single-platform subset gate.
- `registerForRemoteNotifications` (APNs token registration — `UIApplication`/`NSApplication` app-lifecycle).
- O port unificado `NebulaPermissions` request (AV/CL/PH/ATT — app-level glue).

Veja o hub [[nebula-app-readiness-research]] para a sequência de waves (N15 split completo: N15a notifications + N15b background tasks). Próximas: N16 MetricKit → N17 network hardening → N18 StoreKit + A1–A3 Aurora + N11b composition example.
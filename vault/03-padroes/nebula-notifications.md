---
tags: [nebula, architecture, notifications, permissions, usernotifications, swift, concurrency, sendable]
aliases: [nebula notifications, NebulaNotificationCenter, NebulaUNNotificationCenter, NebulaPermissionStatus, NebulaNotificationsConfiguration, nebula notifications tvos gate]
related: [[nebula-background-notifications]], [[nebula-keychain]], [[nebula-preferences]], [[nebula-clean-architecture-toolkit]]
status: shipped
shipped: "0.12.0 (Wave N15a, 2026-07-20)"
---

# Nebula — Notifications + PermissionStatus (shipped)

> Shipped note for the notifications + permission-status dimension of [[nebula-app-readiness-research]] (wave N15a, the lower-risk half of the N15 split). Source of truth: `Sources/Nebula/Architecture/Notifications/` + `Sources/Nebula/Architecture/Permissions/`. Parent research: [[nebula-background-notifications]].

## O que shipou (Nebula 0.12.0)

- **`NebulaPermissionStatus`** — `Sendable`/`Equatable`/`Hashable`/`CaseIterable`/`CustomStringConvertible` enum, union superset de 8 cases (`notDetermined`/`restricted`/`denied`/`authorized`/`provisional`/`ephemeral`/`authorizedAlways`/`authorizedWhenInUse`). `init?(_ status: UNAuthorizationStatus)` bridge: `.notDetermined`/`.denied`/`.authorized`/`.provisional` mapeiam 1:1, `.ephemeral` é `#if os(iOS)` (App Clips), `@unknown default → nil`. All-5, **sem gate** — `UserNotifications` está no floor `.v26` em todas as 5 plataformas. A pasta `Architecture/Permissions/` recebe o type sozinho, forward-looking para o `NebulaPermissions` port deferido.
- **`NebulaNotificationCenter`** — port `Sendable` com 5 requirements (`requestAuthorization(options:) async throws -> Bool`, `add(_:) async throws`, `cancel(_:) async`, `cancelAll() async`, `pendingRequests() async -> [NebulaNotificationRequest]`). Os delegate handlers **não** estão no port — vivem no config (o port é a scheduling surface testável). `NebulaAuthorizationOptions: OptionSet, Sendable` mirror `UNAuthorizationOptions` raw values.
- **`NebulaUNNotificationCenter`** — `final class : NSObject, NebulaNotificationCenter, UNUserNotificationCenterDelegate, Sendable`. Adapter sobre `UNUserNotificationCenter.current()`: instala-se como `delegate` no `init`, forward `willPresent`/`didReceive` para os handlers `@Sendable` no config.
- **Value types** — `NebulaNotificationContent` (title/subtitle/body/userInfo), `NebulaNotificationTrigger` (`.timeInterval`/`.calendar` — `.location` deferido), `NebulaNotificationRequest`, `NebulaNotificationResponse`, `NebulaNotificationPresentationOptions: OptionSet`, todos `Sendable` derived, all-5 (são values Nebula, não SDK props).
- **`NebulaNotificationsConfiguration`** — 6º config, `Sendable` (NÃO `Equatable` — handlers `@Sendable` não são comparáveis), `willPresent: @Sendable (NebulaNotificationRequest) -> NebulaNotificationPresentationOptions` (default `{ _ in [.banner, .sound] }`), `didReceive: @Sendable (NebulaNotificationResponse) -> Void` (default `{ _ in }`), `.withWillPresent`/`.withDidReceive` retornam tipo concreto, `static let default`. `NebulaNotificationsConfig` = caseless `enum` + `Mutex<NebulaNotificationsConfiguration>(.default)` + `get()`/`set(_:)`.
- **`NebulaNotificationsError`** — open-struct (`NebulaFailure, Equatable, Hashable`) + nested `Kind` (presets `notAuthorized`/`schedulingFailed`/`invalidTrigger`/`cancelled`/`unknown`) + `coarseKind` (`schedulingFailed → .cocoa`, resto `→ .unknown`) + `toNebulaError(kind:)` (**sem novos `NebulaError.Kind` cases**). Precedente [[nebula-keychain]].

## Precedente estabelecido: `#if !os(<platform>)` para SDK symbols `API_UNAVAILABLE`

**Esta é a contribuição arquitetural-chave do N15a — e um desvio do plano.** O plano dizia para gatear o override `didReceive` e o mapping de content com `@available(tvOS 26, unavailable)` + `if #available(tvOS 26, *)`. Ambas as formas foram **empiricamente refutadas** via `swiftc -typecheck` contra as 5 SDKs:

- `@available(tvOS, unavailable)` (e `@available(tvOS 26, unavailable)`, que é **sintaxe inválida** — "unavailable can't be combined with shorthand 'tvOS 26'") num override de um requirement de protocolo já-unavailable **falha**: "cannot override 'userNotificationCenter' which has been marked unavailable". Não se pode declarar unavailable algo que o protocolo já marcou unavailable.
- `if #available(..., *)` num symbol `unavailable` **falha**: "'title' is unavailable in tvOS" — o wildcard `*` **NÃO exclui** tvOS para um symbol `unavailable` (ele só cobre platforms onde o symbol *existe*; o symbol não existe em tvOS, então nenhum branch o torna compilável).

A **ÚNICA** forma compile-safe é **`#if !os(tvOS)`** — um compile gate que exclui o symbol do build tvOS inteiramente (o símbolo nunca é referenciado pelo compilador tvOS). N15a aplica `#if !os(tvOS)` em três pontos:

1. O override `userNotificationCenter(_:didReceive:withCompletionHandler:)` — ausente no build tvOS (o requirement do protocolo é unavailable lá, então a conformance não o exige).
2. As atribuições dos props user-facing de `UNMutableNotificationContent` em `makeUNContent` — tvOS constrói um `UNMutableNotificationContent` content-less.
3. A leitura dos props em `makeNebulaContent` — `#if os(tvOS) return NebulaNotificationContent() #else … #endif`.
4. O `makeNebulaResponse` (mapeia `UNNotificationResponse`) — todo envolto em `#if !os(tvOS)`.

**Taxonomia de gating Nebula, agora com 3 formas distintas:**
- `@available(<platform>, unavailable)` — declara um **symbol Nebula** unavailable numa platform (não funciona para override de requirement SDK já-unavailable).
- `#if !os(<platform>)` — compile-gate que exclui um **symbol SDK `API_UNAVAILABLE`** do build daquela platform. ← **precedente N15a**.
- `#if canImport(<framework>)` — whole-file gate para um **framework ausente** numa platform. ← **precedente N15b** (`BackgroundTasks`).

A regra binding `@available(…, *)` com fallback `*` habilita todas as platforms (CLAUDE.md:50) permanece; `#if !os()` é o complemento para symbols unavailable que o `@available`/`#available` não conseguem gatear.

## Decisões de Sendability / shape

- **`final class : NSObject`, não actor** — `UNUserNotificationCenterDelegate` é protocol `@objc` backed por uma referência Obj-C **`weak`**; uma Swift class plain não pode backar um `weak` Obj-C ref → subclass `NSObject` (o precedente `NebulaHTTPServer` `Sendable final class` ganha base `NSObject` aqui). Os delegate methods são **sync Obj-C callbacks**, não `async` entry points; um actor precisaria `nonisolated` + `Mutex` na mesma → `final class` + `Mutex<Config>` é a forma honesta. `Sendable` **derived** (única stored prop é `Mutex<NebulaNotificationsConfiguration>`, que é `Sendable` porque o config é) — **sem `@unchecked`**.
- **`.current()` local, não stored** — `UNUserNotificationCenter` é non-Sendable E um singleton compartilhado; não pode ser `sending`-consumido (o precedente `NebulaDefaults` `Mutex<UserDefaults>` + `sending` **não se aplica**). Cada method chama `UNUserNotificationCenter.current()` localmente; a referência não escapa o method → region isolation satisfeita. `delegate = self` setado **uma vez no init**. `delegate` é `weak` → auto-nila no dealloc → **sem `deinit`** (um `delegate = nil` explícito clobberia o delegate de um façade replacement). O composition root do app deve reter o façade pelo seu lifetime.
- **Handlers synchronous-returning** — `willPresent` retorna `NebulaNotificationPresentationOptions` (não `@Sendable (Options) -> Void`); `didReceive` retorna `Void` (não `@Sendable () -> Void`). Isto evita capturar o completion handler Obj-C non-`Sendable` do SDK dentro de uma closure `@Sendable` — um wall de strict concurrency do Swift 6 que a shape completion-callback (do plano) bateria. O façade invoca o handler e ele mesmo resume o completion do SDK com o resultado síncrono. **Desvio do plano** (o plano tinha `willPresent: @Sendable (Request, @Sendable (Options) -> Void) -> Void`).
- **Region isolation em `pendingRequests`** — resumir uma continuation com um array non-Sendable (`[UNNotificationRequest]`) é erro de region isolation. Solução: mapear para values Nebula Sendable **DENTRO** do completion do SDK (`requests.map(Self.makeNebulaRequest)`), antes de `continuation.resume(returning:)`.
- **`withCheckedThrowingContinuation`** em volta de `requestAuthorization`/`add` (resume once, precedente `NebulaHTTPServer`).

## Limitação de teste: o trap do `.current()` no headless test bundle

`UNUserNotificationCenter.current()` **trapa** (signal 6, aborta todo o run swift-testing) num headless test bundle — não há app context. A primeira tentativa de um integration test `addPendingAndCancelRoundTrip` que instanciava `NebulaUNNotificationCenter()` (cujo init chama `.current().delegate = self`) crashou o bundle inteiro. **Fix:**

- **Nenhum teste instancia o façade** ou chama `.current()`. O teste `facadeIsAPortConformer` é **type-level** (`let centerType: any NebulaNotificationCenter.Type = NebulaUNNotificationCenter.self`; `#expect(centerType is NebulaUNNotificationCenter.Type)`) — prova a conformance sem instanciar.
- Os mapping helpers (`makeUNRequest`/`makeNebulaRequest`/`makeUNContent`/`makeNebulaContent`/`makeNebulaTrigger`/`makeNebulaResponse`) são `internal` (não `private`) para o test module round-trip por types SDK constructíveis (`UNNotificationRequest`, `UNMutableNotificationContent`, `UNTimeIntervalNotificationTrigger`, `UNCalendarNotificationTrigger`) **sem tocar o singleton**. Funções puras — sem risco em expor internamente.
- O path `#if !os(tvOS)` do content roda no host macOS (não-tvOS), então o round-trip cobre o mapping completo.
- **Não testado:** `makeNebulaResponse` (mapeia `UNNotificationResponse`) — `UNNotificationResponse` não tem init público (`init NS_UNAVAILABLE`, system-only-constructible), é dois field reads, coberto por conformance compile-time + limitação documentada.
- **Não testado:** o branch "unsupported trigger → nil" de `makeNebulaTrigger` — os únicos `UNNotificationTrigger` constructíveis são timeInterval e calendar (ambos suportados); `UNPushNotificationTrigger`/`UNLocationNotificationTrigger` herdam `init NS_UNAVAILABLE` e são system-only. O branch `nil` é coberto por `nilTriggerMapsToNil`; o unsupported branch é coberto por conformance + limitação documentada.
- **Port seam** — `FakeNotificationCenter: NebulaNotificationCenter` (in-memory `[String: NebulaNotificationRequest]` em `Mutex`) prova que a scheduling surface é testável sem o center real (precedente `MapFlags`/`InMemoryPrefs`).

## Raw values OptionSet (mirror Apple, verificado nos headers)

- `NebulaAuthorizationOptions`: badge=1, sound=2, alert=4, criticalAlert=16 (1<<4), providesAppNotificationSettings=32 (1<<5), provisional=64 (1<<6). Non-contiguous (1<<3 reserved).
- `NebulaNotificationPresentationOptions`: badge=1, sound=2, list=8 (1<<3), banner=16 (1<<4). 1<<2 é o deprecated `.alert`.

## UNVERIFIED / caveats

- A thread-safety do `UNUserNotificationCenter` para as chamadas locais `.current()` é Apple-documented thread-safe (não reverified neste wave).
- A conformance `Sendable` do façade depende de `UNUserNotificationCenterDelegate` ser `@objc` (não impõe `@MainActor`); o delegate roda numa queue interna do UN — os handlers `@Sendable` capturam só `Mutex`-guarded state.

## Deferred (fora do N15a)

- `.location` trigger (precisa `import CoreLocation` + gate 3-platform).
- `setBadgeCount` (watchOS unavailable), `setNotificationCategories`/`getDelivered*`/`removeDelivered*` (tvOS unavailable), `openSettingsFor` delegate (watchOS+tvOS unavailable).
- `NebulaPermissions` request port unificado (AV/CL/PH/ATT adapters — app-level glue; só `NebulaPermissionStatus` é hoisted agora) + as bridges AV/CL/PH/ATT status.
- `registerForRemoteNotifications` (APNs token registration) — vive em `UIApplication`/`NSApplication`, app-lifecycle.
- **`NebulaBackgroundTask`** → **N15b** (0.13.0): `#if canImport(BackgroundTasks)` whole-file gate + iOS-27 async `submitTaskRequest(_:)` + open-struct error. Ver [[nebula-background-notifications]].

## Builds on / links

- [[nebula-background-notifications]] — parent research (notifications + permission dimension shipped → aqui; background-tasks stays researched → N15b).
- [[nebula-keychain]] — open-struct error precedent (`NebulaKeychainError.Kind`/`coarseKind`/`toNebulaError(kind:)`, sem novos `Kind`) + Port+Façade+Config shape.
- [[nebula-preferences]] — port+façade testability precedent (one-conformer port + in-memory fake).
- [[nebula-clean-architecture-toolkit]] — `NebulaFailure`/`NebulaError`/`Nebula*Config` family idioms.
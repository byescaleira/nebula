---
tags: [nebula, architecture, background-tasks, notifications, permissions, swift]
aliases: [nebula background tasks, NebulaBackgroundTask, NebulaNotifications, NebulaPermissionStatus, BGTaskScheduler, UNUserNotificationCenter, nebula permissions]
related: [[nebula-app-readiness-research]], [[nebula-preferences]], [[nebula-notifications]]
status: researched
researched: "2026-07-19"
---

# Nebula — Background tasks + push notifications + permissions

> Research depth for the background/notifications/permissions dimension of [[nebula-app-readiness-research]]. Verified against `BackgroundTasks.framework/Headers/*.h` + `UserNotifications.framework/Headers/*.h` (Xcode 27 Beta 3), cross-checked per-platform via `swiftc -typecheck` em iphoneos/macosx/appletvos/watchos/xros SDKs. UNVERIFIED items flagged inline.
>
> **Status split (2026-07-20):** the **notifications + permission-status** dimension **SHIPPED** as wave N15a / Nebula 0.12.0 → see [[nebula-notifications]] (it establishes the `#if !os(<platform>)` gating precedent, deviating from this note's original `@available(tvOS 26, unavailable)` / `if #available` recommendation — both empirically invalid for an already-unavailable SDK symbol). The **background-tasks** dimension stays `researched` → wave **N15b** (0.13.0, `#if canImport(BackgroundTasks)` whole-file gate + iOS-27 async `submitTaskRequest(_:)`).

## Dimension overview

Três surfaces Apple que uma architecture library poderia wrap: (a) `BackgroundTasks` (system-initiated background work), (b) `UserNotifications` (local + remote scheduling, authorization, delegate routing), (c) per-framework permission requests (sem API Apple unificada). Todos são Foundation-tier system frameworks (sem UIKit/SwiftUI import para a surface request/scheduling/authorization), mas **todo tipo Apple envolvido é non-Sendable `NSObject` subclass** → qualquer exposure Nebula deve usar `final class` façade + `@Sendable` handler config idiom, copiando payloads para Sendable value types.

## Apple-native APIs + best-practice pattern

### (a) BackgroundTasks — `BGTaskScheduler`
- `BGTaskScheduler.shared` (`sharedScheduler`, `BGTaskScheduler.h:64`) — `API_AVAILABLE(ios(13.0), tvos(13.0)) API_UNAVAILABLE(macos) API_UNAVAILABLE(watchos)`. **visionOS: AVAILABLE** (verified — `swiftc -typecheck` em xros compila `BGTaskScheduler.shared` clean; header omite `visionos` de `API_UNAVAILABLE`, e Apple só marca visionOS unavailable quando intencional, ex. iOS-26 ContinuedProcessing APIs em `BGTask.h:127`/`BGTaskRequest.h:114,130,136` explicitamente `API_UNAVAILABLE(macos, tvos, visionos, macCatalyst)`).
- `register(forTaskWithIdentifier:using:launchHandler:)` (`BGTaskScheduler.h:91`). Deve ser chamado **antes do app finish launching**; system mata o app numa segunda registration do mesmo identifier. `launchHandler: (BGTask) -> Void` é o callback system.
- `submit(_:)` (Swift name de `submitTaskRequest:error:`) — `BGTaskScheduler.h:106`, **deprecated `ios(13.0, 27.0), tvos(13.0, 27.0)`**. Substituído por:
- `submitTaskRequest(_:completionHandler:)` — `BGTaskScheduler.h:140`, `API_AVAILABLE(ios(27.0), tvos(27.0))`, `NS_SWIFT_ASYNC_NAME(submitTaskRequest(_:))` → Swift `async throws`. **O async API do floor Nebula-26.**
- `BGTask` base (`BGTask.h:16`); `setTaskCompleted(success:)`, `expirationHandler: () -> Void` (`BGTask.h:42`, system nils após fire para break retain cycles).
- `BGAppRefreshTask` (`BGTask.h:114`), `BGProcessingTask` (`BGTask.h:85`), `BGAppRefreshTaskRequest` (`BGTaskRequest.h:41`), `BGProcessingTaskRequest` (`BGTaskRequest.h:60` com `requiresNetworkConnectivity`/`requiresExternalPower`).
- **NEW iOS-26-only**: `BGContinuedProcessingTask` + `BGContinuedProcessingTaskRequest` + `supportedResources` (`BGTask.h:127`, `BGTaskRequest.h:114/130/136`, `BGTaskScheduler.h:72`) — `API_AVAILABLE(ios(26.0)) API_UNAVAILABLE(macos, tvos, visionos, macCatalyst) API_UNAVAILABLE(watchos)`. Tem `title`/`subtitle`, `NSProgressReporting`, submission `Strategy` (`.fail`/`.queue`), `Resources`. **iOS-only no floor 26.**
- Error codes (`BGTaskScheduler.h:24`): `Unavailable`, `TooManyPendingTaskRequests`, `NotPermitted`, `ImmediateRunIneligible`.
- Limits: 1 refresh + 10 processing pending. `earliestBeginDate` ≤ 1 semana.
- `Info.plist` `BGTaskSchedulerPermittedIdentifiers` (reverse-DNS strings) required.
- **Best practice** (WWDC19 707 "Advances in App Background Execution"): register identifiers no launch em `didFinishLaunching`; set `expirationHandler` então sempre `setTaskCompleted(success:)`; re-schedule dentro do handler para recurring refresh; `requiresExternalPower=true` desabilita CPU Monitor para processing intensivo; physical-device only (Simulator unsupported). LLDB `e -l objc -- [[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:]`.

### (b) UserNotifications — `UNUserNotificationCenter`
- `UNUserNotificationCenter.current()` (`UNUserNotificationCenter.h:48`) — `API_AVAILABLE(macos(10.14), ios(10.0), watchos(3.0), tvos(10.0))`. **Disponível nas 5 plataformas** (visionOS herdado; verificado por typecheck nas 5 SDKs).
- `requestAuthorization(options:)` (`UNUserNotificationCenter.h:53`). `UNAuthorizationOptions` (`:32`); `.provisional`/`.providesAppNotificationSettings`/`.criticalAlert` ios 12/macOS 10.14.
- `delegate` (`UNUserNotificationCenter.h:42`) — `weak id<UNUserNotificationCenterDelegate>` → **deve ser class** (não value type). Protocol (`:91`):
  - `willPresentNotification:withCompletionHandler:` — 5 plataformas.
  - `didReceiveNotificationResponse:withCompletionHandler:` — `API_UNAVAILABLE(tvos)` (`:100`).
  - `openSettingsForNotification:` — `API_UNAVAILABLE(watchos, tvos)`.
- `UNNotification`/`UNNotificationRequest`/`UNNotificationTrigger`/`UNPushNotificationTrigger`/`UNTimeIntervalNotificationTrigger`/`UNCalendarNotificationTrigger` — todos `API_AVAILABLE(macos(10.14), ios(10.0), watchos(3.0), tvos(10.0))`.
- `UNNotificationResponse` — `API_UNAVAILABLE(tvos)`.
- `UNLocationNotificationTrigger` — `API_AVAILABLE(ios(10.0), watchos(3.0)) API_UNAVAILABLE(macos, tvos, macCatalyst, visionos)` — iOS + watchOS only.
- **`UNNotificationContent`/`UNMutableNotificationContent`** — base type disponível 5 plataformas, MAS **toda prop user-facing** (`title`/`body`/`subtitle`/`sound`/`userInfo`/`attachments`/`categoryIdentifier`/`threadIdentifier`) é `API_UNAVAILABLE(tvos)` (`UNNotificationContent.h:39-66, 101-128`). Notificações tvOS são content-less system signals, não user-facing alerts.
- `setNotificationCategories:`/`getNotificationCategories`/`getDeliveredNotifications`/`removeDeliveredNotifications`/`removeAllDeliveredNotifications` — todos `API_UNAVAILABLE(tvos)`.
- `setBadgeCount:` — `API_AVAILABLE(macos(13.0), ios(16.0), tvos(16.0)) API_UNAVAILABLE(watchos)`.
- **Best practice** (WWDC "What's new in User Notifications"): request authorization num momento significativo (não first launch a menos justificado); prefira `.provisional` para trial delivery; route `willPresent`/`didReceive` payloads para app logic via port; para remote push, APNs requer entitlement + push token registration (`registerForRemoteNotifications` em `UIApplication`/`NSApplication` — app-lifecycle, não job Nebula). UI presentation (banner/sound/badge options, `UNNotificationContentExtension`, SwiftUI `NotificationContent` modifier) é UIKit/SwiftUI-tier → **fora do escopo Nebula**.

### (c) Permissions — sem API Apple unificada
- Cada framework gate a sua: `AVCaptureDevice.requestAccess(for:)` (AVFoundation, camera/mic), `CLLocationManager.requestWhenInUseAuthorization`/`requestAlwaysAuthorization` (CoreLocation), `PHPhotoLibrary.requestAuthorization(for:)` (Photos), `ATTrackingManager.requestTrackingAuthorization` (AppTrackingTransparency, iOS 14+, `API_UNAVAILABLE(macos, tvos, watchos)` — iOS-only), `UNUserNotificationCenter.requestAuthorization`.
- Cada uma tem status enum distinto (`AVAuthorizationStatus`/`CLAuthorizationStatus`/`PHAuthorizationStatus`/`ATTrackingManagerAuthorizationStatus`/`UNAuthorizationStatus`) com vocabulários não-idênticos.
- Todas request calls são Foundation-tier (sem UIKit import) EXCETO o prompt UX é system-driven (dialog Apple, não app UI). ATT requer a capability App Tracking Transparency.
- **Best practice**: prompt num momento significativo just-in-time (decisão UX/app); in-app pre-permission gate; check status antes de request. Sem abstraction unificada Apple-endorsed — toda lib "permissions" OSS é app-level glue.

## Sendability & availability

| API | Sendable? | iOS/macOS/tvOS/watchOS/visionOS | Gate? |
|---|---|---|---|
| `BGTaskScheduler`/`BGTask`/`BGAppRefreshTask`/`BGProcessingTask`/`BGTaskRequest` subclasses | Não | 13+/unavailable/13+/unavailable/available | **Sim — explicit per-platform unavailable**: `@available(iOS 26, tvOS 26, visionOS 26, *)` + `@available(macOS 26, unavailable)` + `@available(watchOS 26, unavailable)`. **NÃO `@available(iOS 13, *)`** (o `*` fallback habilita todos — proibido) |
| `BGContinuedProcessingTask` + Request + `supportedResources` | Não | 26+/unavailable/unavailable/unavailable/unavailable | Sim — iOS-only subset gate |
| `submitTaskRequest(_:completionHandler:)` (async) | closure → bridged `async` | 27+/unavailable/27+/unavailable/available | Sim — `@available(iOS 27, tvOS 27, visionOS 27, *)` + unavailable mac/watch |
| `UNUserNotificationCenter` + `requestAuthorization` + `UNNotification`/`Request`/`Trigger` (time/calendar/push) | Não | 10+/10.14+/10+/3+/available | Mínimo — 5 plataformas no floor |
| `UNUserNotificationCenterDelegate.didReceive` + `UNNotificationResponse` | Não | 10+/10.14+/unavailable/3+/available | Sim — tvOS-unavailable subset |
| `UNNotificationContent`/`UNMutableNotificationContent` user-facing props | Não | 10+/10.14+/unavailable/3+/available | Sim — tvOS-unavailable subset |
| `UNLocationNotificationTrigger` | Não | 10+/unavailable/unavailable/8+/unavailable | Sim — iOS+watchOS only |
| `setBadgeCount:` | Não | 16+/13+/16+/unavailable/available | Sim — watchOS-unavailable subset |
| Permission frameworks (AVFoundation/CoreLocation/Photos/AppTrackingTransparency) | Não (NSObject managers) | varia | Per-framework. ATT iOS-only. Importar alarga a surface Nebula |

## Nebula-scope verdict

| Surface | Veredito | Rationale | Tensão |
|---|---|---|---|
| **`NebulaBackgroundTask`** — port (identifiers, request value types) + config (`@Sendable` launch/expiration handlers) + `final class` façade sobre `BGTaskScheduler` | **Port + Façade + Config** | Foundation-tier; non-Sendable Apple types precisam façade; `register`/`submit`/`setTaskCompleted` mapeiam para port + `@Sendable` handler config. New iOS-27 `submitTaskRequest(_:)` async é port Swift `async` natural | Platform gate: iOS/tvOS/visionOS only → **MUST** explicit `@available(macOS 26, unavailable)` + `@available(watchOS 26, unavailable)` (o `@available(iOS 13, *)` `*`-fallback é proibido). `register`-before-launch é hook app-lifecycle — Nebula expõe o port, app chama do launch site. iOS-26 `BGContinuedProcessingTask` é iOS-only no floor → subset gate separado |
| **`NebulaNotifications`** — port (schedule/cancel/authorization value types) + config (`@Sendable` `willPresent`/`didReceive` payload handlers) + `final class` delegate-adapter (conforms `UNUserNotificationCenterDelegate`, forward para `@Sendable` handlers) | **Port + Façade + Config** | Foundation-tier (scheduling, authorization, delegate payload routing). UI presentation (banner/sound options, `NotificationContent` SwiftUI modifier, content extensions) é UIKit/SwiftUI → Cosmos/app. O `weak` delegate deve ser class → adapter façade mandatório | All 5 → standard 5-platform `@available` gate. Sub-APIs tvOS-unavailable (`didReceive`, `UNNotificationResponse`, content props, delivered-notification management) → subset gates `@available(tvOS 26, unavailable)`. Authorization vive aqui (não num port permissions genérico) porque UN já está em scope |
| **`NebulaPermissionStatus`** — unified Sendable value-type enum (`notDetermined`/`restricted`/`denied`/`authorized`/`provisional`/`ephemeral`/`authorizedAlways`/`authorizedWhenInUse`) | **Value (include, small)** | Pure Foundation value type, sem framework imports (app mapeia cada status enum framework para ele). Unifica o vocabulário sem acoplar Nebula a AV/CoreLocation/Photos/ATT | Low. Deve acknowledge que é superset union — alguns cases não aplicam a cada framework (app handles mapping). Derive `Sendable` |
| **`NebulaPermissions`** — unified request port wrapping AV/CL/PH/ATT/UN | **Defer / App-only** | Sem API Apple unificada; cada framework tem signature distinta (async vs completion-handler vs status-then-request) + prompt system-driven. O "momento significativo" para prompt é decisão UX/app, não architecture. Importar 4+ system frameworks alarga a surface Nebula além de uma foundation/architecture library | `dependencies: []` stays pristine (system frameworks não são third-party), mas a *surface* explode. ATT iOS-only → forçaria per-platform unavailable gates para uma permission. Melhor como app-level glue ou companion package separado. O status value type (acima) é a única peça que vale hoist |
| Notification UI presentation (banner/sound/badge options, `UNNotificationContentExtension`, SwiftUI `NotificationContent`) | **Cosmos-only / App-only** | UIKit/SwiftUI tier — binding rule proíbe UIKit/SwiftUI em Nebula | Hard exclusion per CLAUDE.md |
| `registerForRemoteNotifications` (APNs token registration) | **App-only** | Vive em `UIApplication`/`NSApplication` (app-lifecycle delegate), não em `UNUserNotificationCenter` | UIKit/AppKit-tier; Nebula pode definir o tipo `@Sendable` handler para o payload token/error, mas a registration call é do app |

## Recommended waves

- **N15 — Background tasks + notifications.** `NebulaBackgroundTask` (port + config + `final class` façade; `@Sendable` launch/expiration handlers; async `submit` via iOS-27 `submitTaskRequest(_:)`; open-struct errors conforming `NebulaFailure` bridging a `NebulaError.Kind` existente — **sem novos Kind cases**) e `NebulaNotifications` (port + config + `final class` delegate-adapter; `@Sendable` `willPresent`/`didReceive` handlers; authorization + scheduling/cancel; tvOS-unavailable subset gates). Plus o small `NebulaPermissionStatus` value type. Deps: ambos buildam sobre os idioms `NebulaError`/`Nebula*Config` existentes; sem inter-dependência entre os dois. Platform gates: BackgroundTask = iOS/tvOS/visionOS (explicit macOS+watchOS unavailable); Notifications = all 5 com tvOS-unavailable subsets.
- **(Defer) N?? — Permissions port**: só se demanda real emergir; importaria AVFoundation/CoreLocation/Photos/AppTrackingTransparency + per-framework request adapters. Recomendar manter como app-level glue a menos que um sibling package materialize.

## UNVERIFIED (não citar como fato)
- `UNNotificationAttributedMessageContext` per-platform availability lines (file existe nos headers mas não grep das `@interface`/`API_AVAILABLE` lines — flag antes de designar qualquer port attributed-payload).
- visionOS *introduction version* exato para `BGTaskScheduler` (header lista só `ios(13.0), tvos(13.0)`; visionOS implied pela ausência de `API_UNAVAILABLE(visionos)` + confirmado por typecheck, mas o floor `xrs(N)` preciso não está no header — irrelevante pois o floor `.v26` está bem acima).
- Se `BGContinuedProcessingTask`'s `NSProgressReporting` conformance é Sendable (NSProgress não é Sendable por default) — afeta se a façade pode expor o progress publisher sem actor boundary.
- WWDC "What's new in User Notifications" session/year exato para as adições iOS-26 attributed-message — não web-search; a API surface acima é header-verified, a citação WWDC não.

## Sources
- WWDC19 707 "Advances in App Background Execution" — https://developer.apple.com/videos/play/wwdc2019/707/
- Apple — "Refreshing and Maintaining Your App Using Background Tasks" — https://developer.apple.com/documentation/BackgroundTasks/refreshing-and-maintaining-your-app-using-background-tasks
- WWDCNotes 707 — https://wwdcnotes.com/documentation/wwdc19-707-advances-in-app-background-execution/
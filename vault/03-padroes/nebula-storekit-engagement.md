---
tags: [nebula, architecture, storekit, iap, tipkit, appintents, activitykit, cloudkit, swift]
aliases: [nebula storekit, NebulaIAPPort, NebulaStoreKitGateway, nebula engagement, nebula monetization, TipKit scope, AppIntents scope, ActivityKit scope, CloudKit scope]
related: [[nebula-app-readiness-research]], [[nebula-aurora-swiftdata]]
status: researched
researched: "2026-07-19"
---

# Nebula — StoreKit / TipKit / AppIntents / ActivityKit / CloudKit scope verdicts

> Research depth for the engagement/monetization dimension of [[nebula-app-readiness-research]]. Verified Sendability + per-platform availability contra o `.swiftinterface` (Xcode 27 Beta 3) para todos os 5 frameworks. UNVERIFIED items flagged inline.

## Dimension overview

Cinco frameworks Apple-native de engagement/monetization, avaliados contra as binding rules (Foundation-only, derived-Sendable, 5-platform `.v26`, `dependencies: []`, port+config+façade idiom, closed `NebulaError.Kind`). Os eixos decisivos: (a) **Foundation-tier vs UI-coupled** — a *data* surface do framework stands alone, ou os core types requerem `SwiftUI`/`UIKit`? (b) **5-platform availability** — ship em iOS/macOS/tvOS/watchOS/visionOS no `.v26`? (c) **Sendability** — os tipos Apple cruzam actor boundaries sem `@unchecked` num tipo Nebula-defined? O veredito splita clean: **StoreKit 2's transaction layer é o único strong Nebula candidate**; TipKit é SwiftUI-coupled (Cosmos); ActivityKit é iPhone-only (app); CloudKit é non-Sendable-heavy (sibling); AppIntents é Foundation-tier mas inherentemente app-owned (Nebula supplies os use-case ports, app conforms `AppIntent`).

## Per-framework: APIs + best-practice pattern

### (a) StoreKit 2 — Foundation-tier transactions
- `Product` (struct, Sendable, iOS-iface L1875; `@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, visionOS 1.0, *)` L1874) + `Product.products(for:) async throws -> [Product]` (L1934, generic over `Collection<String>`).
- `Product.PurchaseOption` (struct, **inline `Sendable`**, L1786). Factories verified: `appAccountToken(_:)` (L1787), `promotionalOffer(_ offerID:compactJWS:)` (L1810, `@backDeployed` to iOS 26), `quantity(_:)` (L1817), `winBackOffer(_:)` (L1819, iOS 18+), `billingPlanType(_:)` (L1789, **iOS 26.4+ — above floor**). **`.autoRenewableFamilyDiscount` NÃO EXISTE** (absent — não citar).
- `Transaction` (struct, Sendable via ext L1729, L1176; stored props `id: UInt64`/`productID`/`purchaseDate`/`expirationDate`/`ownershipType`/`signedDate` etc. L1285–1604).
- `Transaction.updates` (L1661) — `AsyncSequence<VerificationResult<Transaction>, Never>` (typealias L1631; `Failure == Never` via `@_implements` L1638). **Best practice: background `Task` listening `Transaction.updates`, verify JWS, `finish()`**.
- `Transaction.currentEntitlements` (L1645) e `Transaction.all` (L1642) — mesmo `Transactions` AsyncSequence.
- `VerificationResult<SignedType>` (`@frozen` enum, L1129; cases `.unverified(SignedType, VerificationError)` **listado primeiro**, `.verified(SignedType)`; conditional `Sendable where SignedType: Sendable` L1172; `VerificationError` cases L1137–1142). `payloadValue: SignedType { get throws }` (L1132).
- `Transaction.finish()` — `public func finish() async` (L1604, sem throws).
- `Product.SubscriptionInfo`/`StoreKit.SubscriptionInfo` typealias (L738) — Sendable (ext L799), `Equatable`/`Hashable`.
- `AppStore.sync() async throws` (L2036); `AppStore` enum (L2026, Sendable-by-namespace).
- **UI-coupled APIs para EVITAR em Nebula**: `AppStore.showManageSubscriptions(in:)` (L2048, iOS/macCatalyst/visionOS only), `AppStore.presentMerchandising(_:from:)` (L2059, `@MainActor`, takes `UIViewController`), `Product.purchase(confirmIn:)` (L1864–1872, `UIScene`/`UIViewController`-typed). Esses carregam per-platform `unavailable` gates + UIKit types.
- **Module caveat**: `StoreKit` module faz plain `import UIKit` (iOS L17) / `import AppKit` (macOS L1) — **NÃO `@_exported`**, logo UIKit NÃO é re-exportado para o namespace Nebula. UIKit types aparecem só nas UI-API signatures que Nebula não chamará. WWDC21 "Meet StoreKit testing"; WWDC22 "What's new in StoreKit 2"; WWDC23 "Meet StoreKit for SwiftUI" (SwiftUI overlay — `_StoreKit_SwiftUI`, módulo separado, concern app/Cosmos).

### (b) TipKit — SwiftUI-coupled (NÃO Nebula)
- `@_exported import SwiftUI` na **linha 7 de ambas as interfaces iOS e macOS** — transitivamente exporta SwiftUI para todo importer.
- `Tip` protocol (L368): `var title: SwiftUICore::Text`, `var message: SwiftUICore::Text?`, `var image: SwiftUICore::Image?` (L370–372) — **impossível satisfazer Foundation-only**. Também `Sendable` (L368).
- `Tips` namespace (`@frozen public enum`, L849); `Tips.configure(_:) throws` (L853), `Tips.resetDatastore() throws` (L929 — **NÃO `reloadData()`**), `Tips.showAllTipsForTesting()` (L931 — **NÃO `showAllTips()`**), `Tips.hideAllTipsForTesting()` (L935 — **NÃO `dismissAllTips()`**).
- `Tips.Rule` (struct, Sendable, L298) — **NÃO `DisplayRule`** (não existe). `@Parameter` macro (L249) expande para `Tips.Parameter<Value>` (struct, `Identifiable, Sendable where Value: Codable, Sendable`, L224).
- `TipGroup` (top-level `final public class : Sendable`, L661, iOS 18+/macOS 15+) — **NÃO `Tips.Group`** (não existe). `nonisolated Observable` (L671).
- `Tips.Status` (enum, `Hashable, Sendable`, L628): `.pending`/`.available`/`.invalidated(InvalidationReason)`.
- Floor: `@available(macOS 14.0, iOS 17.0, macCatalyst 17.0, tvOS 17.0, visionOS 1.0, watchOS 10.0, *)` — **abaixo do floor `.v26` do Nebula em toda plataforma**.
- UIKit classes in-module: `TipUICollectionReusableView`/`TipUICollectionViewCell` (iOS L943); `TipNSPopover` (macOS). WWDC23 "Discover TipKit".

### (c) AppIntents — Foundation-tier core, app-owned conformance
- Core module: **SEM `import SwiftUI`, SEM `@MainActor`** em qualquer lugar (verified por grep). Imports: `CoreLocation`/`CoreSpotlight`/`CoreTransferable`/`ExtensionFoundation`/`RelevanceKit`/`UniformTypeIdentifiers` (L5–17). SwiftUI vive no **`_AppIntents_SwiftUI` overlay** (framework separado — `ShortcutsLink: SwiftUICore::View`, `@MainActor`, overlay L22).
- `AppIntent` protocol (L1412): `: Sendable` explícito; `func perform() async throws -> Self.PerformResult` (L1425, **plain async throws, NÃO `@MainActor`**); `static var title: LocalizedStringResource` (L1413).
- `AppShortcutsProvider` (L9003, `: Sendable`); `AppEntity` (L460, Sendable via `AppValue` L2081); `AppEnum` (L1067, Sendable via `AppValue`); `IntentResult` (L2800, `: Sendable`); `IntentResultContainer<...>` (L2827, `@unchecked Sendable`); `EntityIdentifier` (L751, `: Sendable` — **NÃO `AppEntityIdentifier`** que não existe).
- `IntentParameter<Value>` (L2668) e `EntityProperty<Value>` (L2308) — `final public class ... : @unchecked Sendable` (Apple-authored property wrappers; a regra no-`@unchecked` do Nebula não vincula Apple).
- **`AppIntentResult` e `SnippetGroup` NÃO EXISTEM** (absent — não citar). Use `IntentResult`/`IntentResultContainer` e `SnippetIntent` (L1978, `@available(anyAppleOS 26.0, *)` — novo em 26).
- Floor: `@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)` (visionOS via `*` fallback → 1.0). 5 plataformas suportadas para core protocols. WWDC22 "Meet AppIntents"; WWDC24 "Bring your app to Siri with App Intents".

### (d) ActivityKit — iPhone-only (NÃO Nebula)
- **Framework ausente dos tvOS/watchOS/visionOS device SDKs** (verified por directory listing). macOS ship o framework mas toda API é `@available(macOS, unavailable)` + `@available(macCatalyst, unavailable)`. visionOS interface annotations dizem `visionOS 2.0` em algumas iOS-18+ APIs mas a visionOS SDK **não tem ActivityKit.framework** — deve add explicit `@available(visionOS, unavailable)`.
- `Activity<Attributes>` (L41) — **`public class`, NÃO Sendable**, `@_hasMissingDesignatedInitializers`, `final public let id: String` (L89).
- `ActivityAttributes` protocol (L14) — `Decodable, Encodable` only; `ContentState` associatedtype constrained `Decodable, Encodable, Hashable` — **NÃO Sendable**.
- `ActivityContent<State>` (L411) — **struct, conditional `Sendable where State: Sendable`** (ext L419). Floor iOS 16.2.
- `ActivityAuthorizationInfo` (L466 — **NÃO `ActivityKitAuthorizationInfo`**, esse nome não existe) — `final public class`, NÃO Sendable.
- `Activity.request(...)` — **sync `throws`, NÃO async** (quatro overloads L47/L56/L62/L71; floor iOS 16.1; iOS 26.0 adiciona `alertConfiguration:start:`). `Activity.end(...)` — `async` (NÃO throws, L167/L173/L179). **`Activity.dismiss()` NÃO EXISTE** — dismissal via `end(..., dismissalPolicy: ActivityUIDismissalPolicy)` (L455, Sendable).
- `Activity.activityUpdates` (L87 — **NÃO `activityHandleUpdates`**) — `AsyncSequence<Activity<Attributes>, Never>` (L206). `Activity.activities` é um plain `[Activity<Attributes>]` array (L86).
- `ActivityState` enum (L379) — `Sendable, Codable, Hashable`. Floor iOS 16.1 (NÃO 16.2).
- **Sem `import SwiftUI`/`import WidgetKit`** em ActivityKit; UI vive em SwiftUI. WWDC22 "Meet ActivityKit"; WWDC23 "What's new in ActivityKit".

### (e) CloudKit — non-Sendable-heavy, sibling-package candidate
- 5 plataformas (framework presente em todo SDK). Floor: base `macOS 10.10/iOS 8.0/tvOS 9.0/watchOS 3.0`; modern async overlay `macOS 12.0/iOS 15.0/tvOS 15.0/watchOS 8.0` (visionOS 1.0 via `*`).
- **Sendability é a binding-rule tension.** `@objc` NSObject subclasses; a `.swiftinterface` contém só Swift-added extensions (base classes vivem em ObjC headers).
  - **NÃO Sendable** (sem extension): `CKContainer`/`CKDatabase`/`CKRecord.ID`/`CKRecordID`/`CKRecord.Reference`/todos `CKOperation` subclasses (`CKQueryOperation`/`CKModifyRecordsOperation`/`CKFetchRecordsOperation` etc. — são `NSOperation` subclasses)/`CKError`.
  - **`@unchecked Sendable`** (Apple-authored, acima macOS 14.0/iOS 17.0): `CKRecord` (L807)/`CKQuery` (L777)/`CKShare` (L1074)/`CKShare.Participant` (L1147)/`CKAsset` (L11)/`CKRecordZone` (L1019)/`CKRecordZone.ID` (L1040, floor macOS 13.3/iOS 16.4)/`CKUserIdentity` (L1277)/`CKSubscription` (L1219)/`CKQuery.Cursor` (L1314)/`CKOperation.Configuration` (L1610)/`CKOperationGroup` (L1613).
  - **Genuinely Sendable (non-`@unchecked`)**: só `CKSyncEngine` — `final public class CKSyncEngine : Swift::Sendable` (L1617, `@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)`), + nested `Configuration`/`Event`/`StateUpdate`/`FetchedDatabaseChanges` structs (todos Sendable, L1641+).
- **Async/await overlay** em `CKContainer`/`CKDatabase` é robusto: `record(for:)` (L451)/`records(matching:inZoneWith:)` (L530)/`save(_:)` (L474)/`modifyRecords(saving:deleting:)` (L515)/`allRecordZones()` (L534)/`fetchDatabaseChanges(since:)` (L664)/`fetchRecordZoneChanges(inZoneWith:)` (L684)/`shareParticipant(forEmailAddress:)` (L206)/`accept(_:)` (L300) etc. — floor macOS 12.0/iOS 15.0.
- **`CKContainer.accountStatus(completionHandler:)` NÃO tem variante async** (sem `NS_SWIFT_ASYNC` annotation) — precisa wrapper manual `withCheckedThrowingContinuation`.
- `database(withPublicScope:)` está **incorreto** — API real é `database(withDatabaseScope:)` tomando `CKDatabaseScope` (CKContainer.h:134).
- "No public database on watchOS" claim: **UNVERIFIED da `.swiftinterface`** — sem `API_UNAVAILABLE(watchos)` em `CKDatabaseScopePublic`; qualquer restrição é runtime/entitlement, não em headers.
- Sem `import SwiftUI`; `_CoreData_CloudKit` é overlay separado (não re-exported). WWDC22 "Meet CKSyncEngine" (o entry point Sendable); WWDC23 "What's new in CloudKit".

## Sendability & availability table

| Framework / API | Sendable? | Floor (per platform) | Gate? |
|---|---|---|---|
| **StoreKit 2** `Product`/`Transaction`/`VerificationResult`/`Transaction.updates`/`all`/`currentEntitlements`/`AppStore.sync` | Sim (ext L1964/L1729/L1172) | iOS 15/macOS 12/tvOS 15/watchOS 8/visionOS 1 | Sim — 5-platform `@available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)` para surface Nebula |
| `Product.PurchaseOption` | Sim (inline) | mesmo; `billingPlanType` iOS 26.4+ | mesmo + above-floor gate para 26.4 factories |
| StoreKit UI APIs (`showManageSubscriptions`/`presentMerchandising`/`purchase(confirmIn:)`) | n/a | iOS/macCatalyst/visionOS only; macOS/tvOS/watchOS `unavailable` | **NÃO usar em Nebula** — `UIViewController`/`UIScene`-typed |
| **TipKit** `Tip` protocol | Sim (L368) | iOS 17/macOS 14/tvOS 17/watchOS 10/visionOS 1 — **abaixo .v26** | N/A — NÃO Nebula (`@_exported import SwiftUI` L7; `title/message/image` são `SwiftUICore.Text`/`Image`) |
| `Tips.Rule`/`Parameter<Value>`/`Status` | Sim | mesmo | N/A |
| **AppIntents** `AppIntent`/`AppShortcutsProvider`/`AppEntity`/`AppEnum`/`IntentResult`/`EntityIdentifier` | Sim (explícito ou via `AppValue`) | iOS 16/macOS 13/tvOS 16/watchOS 9/visionOS 1 | Sim para qualquer surface Nebula-touched |
| `IntentParameter`/`EntityProperty`/`IntentResultContainer` | `@unchecked Sendable` (Apple-authored) | mesmo | n/a (regra Nebula não vincula Apple) |
| `ShortcutsLink` | Sim (overlay ext) | iOS 16+ (`*` fallback) | N/A — NÃO Nebula (overlay `_AppIntents_SwiftUI`; `: SwiftUICore::View`, `@MainActor`) |
| `SnippetIntent` | Sim (via `AppIntent`) | `@available(anyAppleOS 26.0, *)` | alinha com Nebula 26 |
| **ActivityKit** `Activity<Attributes>` | **NÃO** (class) | iOS 16.1 only; macOS/tvOS/watchOS `unavailable`; visionOS SDK sem framework | Hard 5-platform gate: `@available(iOS 26, *)` + `@available(macOS, unavailable)` + `@available(tvOS, unavailable)` + `@available(watchOS, unavailable)` + `@available(visionOS, unavailable)` |
| `ActivityAttributes`/`ContentState` | **NÃO** (Decodable+Encodable+Hashable only) | iOS 16.1 | mesmo |
| `ActivityContent<State>` | Sim (conditional `where State: Sendable`, L419) | iOS 16.2 | mesmo |
| `ActivityState` enum | Sim (L379) | iOS 16.1 | mesmo |
| `ActivityAuthorizationInfo` | **NÃO** (final class) | iOS 16.1 | mesmo |
| `Activity.request`/`end` | n/a | iOS 16.1/16.2/18.0/26.0 per overload | mesmo |
| **CloudKit** `CKContainer`/`CKDatabase`/`CKRecord.ID`/`CKOperation` subclasses/`CKError` | **NÃO** | macOS 10.10/iOS 8/tvOS 9/watchOS 3 | Sim para qualquer surface Nebula-touched |
| `CKRecord`/`CKQuery`/`CKShare`/`CKAsset`/`CKRecordZone`/`CKUserIdentity`/`CKSubscription` | `@unchecked Sendable` (Apple-authored) acima macOS 14/iOS 17 | macOS 14/iOS 17/tvOS 17/watchOS 10 | 5-platform gate OK em .v26 |
| `CKSyncEngine` | **Sim (genuine, non-`@unchecked`, L1617)** | macOS 14/iOS 17/tvOS 17/watchOS 10 | 5-platform gate OK |
| `CKContainer.accountStatus` | n/a | macOS 10.10/iOS 8/watchOS 3 | n/a — **sem variante async** (wrapper manual) |
| CKDatabase async overlay | n/a | macOS 12/iOS 15/tvOS 15/watchOS 8 | 5-platform gate OK |

## Nebula-scope verdict

| Framework | Veredito | Rationale | Tensão |
|---|---|---|---|
| **StoreKit 2** | **Port+Façade in Nebula** (data/transaction layer only) | `Product`/`Transaction`/`VerificationResult`/`AppStore.sync`/`Transaction.updates` são Sendable value types/AsyncSequences nas 5 plataformas; o IAP data path é Foundation-tier (transactions, sem UI). Match o idiom `NebulaGateway`/`NebulaRepository` port — `NebulaIAPPort`/`NebulaStoreKitGateway` façade sobre `Transaction.updates` + `Transaction.finish()` + `Product.products(for:)`. UI APIs ficam app-side | **UIKit-import tension (manageable)**: módulo StoreKit faz plain `import UIKit`/`import AppKit` (não `@_exported` → UIKit NÃO re-exportado para namespace Nebula). Nebula nunca author UIKit symbols nem chama APIs UIViewController-typed. Consistente com "Foundation APIs that wrap UIKit internally are not invoked from Nebula." `NebulaError.Kind` é closed — IAP failures bridge para `.network`/`.cocoa`/`.unknown` existentes (**sem novos Kind cases**) |
| **TipKit** | **Cosmos-only** (ou app) | `@_exported import SwiftUI` (L7) + `Tip.title/message/image` requerem `SwiftUICore.Text`/`Image` (L370–372) — não existe declaration layer Foundation-tier. UIKit/AppKit bridging classes in-module | **Hard NO para Nebula**: viola "Foundation-only, no SwiftUI, no UIKit" + "Never author UIKit symbols." Floor (iOS 17/macOS 14) também abaixo `.v26`. Cosmos (sibling SwiftUI) é o home natural |
| **AppIntents** | **App-owned** (Nebula supplies use-case ports; app conforms `AppIntent`) | Core module Foundation-tier (sem SwiftUI, sem `@MainActor`), todos core protocols Sendable, 5 plataformas. Mas `AppIntent` implementations inherentemente referenciam app domain types (Siri/Shortcuts/Spotlight intents são app-level). Nebula não wrap AppIntents — o app's `AppIntent.perform()` delega para um Nebula use-case port (`NebulaUseCase` da Wave H). Sem nova surface Nebula | **Nenhuma tensão** — o port use-case Wave H existente É o seam. App conforma `AppIntent`; `perform()` chama `await useCase.execute(...)`. Nebula adiciona zero symbols AppIntents. `SnippetIntent` new-in-26 alinha com baseline Nebula 26 se um future example quiser demonstrar |
| **ActivityKit** | **App-only** (ou sibling package se Live Activities virarem first-class) | iPhone-only — framework ausente dos tvOS/watchOS/visionOS device SDKs; macOS APIs todas `@available(macOS, unavailable)`. `Activity<Attributes>` é non-Sendable class. Os `ActivityAttributes`/`ContentState` Codable value types são Nebula-adjacent data, mas a violação 5-platform é hard gate | **Hard 5-platform violation**: não satisfaz "all 5 platforms at `.v26`." Qualquer wrapper Nebula precisaria `@available(iOS 26, *)` + explicit `@available(macOS, unavailable)` + `@available(tvOS, unavailable)` + `@available(watchOS, unavailable)` + `@available(visionOS, unavailable)` (o gate visionOS MUST ser explicit — as annotations `visionOS 2.0` do lado iOS são misleading porque a visionOS SDK não ship framework). Também `Activity` class non-Sendable → `actor` ou region-based isolation, não `@unchecked` |
| **CloudKit** | **Sibling-package** (Aurora-style) ou **Defer** | Foundation-tier (sem SwiftUI) e 5 plataformas, mas as marquee `CK*` classes são `@objc` NSObjects que são ou non-Sendable (`CKContainer`/`CKDatabase`/`CKRecord.ID`/`CKOperation` subclasses) ou `@unchecked Sendable` (Apple-authored, acima iOS 17). `CKSyncEngine` (OS 27 SDK, L1617) é o único entry point genuinely-Sendable. Não encaixa na regra "derive, never `@unchecked`" do Nebula para wrappers Nebula-defined — uma façade `actor`-isolated (como Aurora's `@ModelActor`) quer seu próprio module graph | **Sendable + module-graph tension**: espelha a decisão Aurora (SwiftData) — non-Sendable Apple types + façade `@ModelActor`/`actor`-isolated → sibling package para `import <CloudKitSibling>` de Nebula ser hard compile error (enforces "domain never import persistence" across packages). `CKContainer.accountStatus` sem async → o sibling package fornece o wrapper `withCheckedThrowingContinuation`. Design CKSyncEngine-first recommended |

## Recommended waves

- **N18 — StoreKit IAP port** (Port+Façade in Nebula). `NebulaIAPPort` (use-case port: `purchase(productID:) async throws -> NebulaIAPResult`, `entitlements(for:) async -> AsyncThrowingStream<NebulaIAPTransaction, Never>`), `NebulaStoreKitGateway` (`final class`/`actor` façade sobre `Product.products(for:)` + `Transaction.updates` listener + `Transaction.finish()` + `VerificationResult` JWS verification), `NebulaIAPConfig` (`Mutex<NebulaIAPConfiguration>` process-wide accessor, paralelo a `NebulaGatewayConfig`), open-struct `NebulaIAPError: NebulaFailure` bridging para `NebulaError.Kind.network`/`.cocoa`/`.unknown` existentes (**sem novos Kind cases**). 5-platform `@available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)`. Deps: toolkit Wave H (`NebulaGateway`/`NebulaFailure`/`NebulaError`). **Strong candidate — implementar primeiro** (dos Tier 3).
- **N?? — AppIntents use-case binding example** (App-owned, doc-only em Nebula). DocC article + runnable example mostrando um app `AppIntent.perform()` delegando para um Nebula `NebulaUseCase` port (sem novos symbols Nebula). Deps: toolkit Wave H use-case port. Esforço baixo. Opcional.
- **DEFER — ActivityKit sibling package** (app-only ou sibling). Só se/quando Live Activities virarem concern first-class do app. iPhone-only → deve ser sibling package (espelha Meridian/Aurora) para `import <ActivitySibling>` de Nebula ser hard compile error; explicit per-platform `@available(<platform>, unavailable)` gates. `actor`-isolated sobre non-Sendable `Activity<Attributes>`. Deps: app pull. **DEFER até um segundo use justificar.**
- **DEFER — CloudKit sibling package** (Aurora-style). `CKSyncEngine`-first Sendable façade (`final public class ... : Sendable` wrap `CKSyncEngine`), `actor`-isolated `CKDatabase`/`CKContainer` adapter, `accountStatus` async continuation wrapper, `NebulaCloudKitError: NebulaFailure` bridging para `.network`/`.cocoa`. Pacote local SwiftPM separado (`path: "../`) para `import <CloudKitSibling>` de Nebula ser hard compile error. Deps: app pull + verificação `CKSyncEngine` em OS 27 (`@available` macOS 14/iOS 17, disponível em `.v26`). **DEFER — pesado; revisit quando CloudKit sync earns um segundo use.**
- **Cosmos wave (fora do Nebula)** — TipKit tip-declaration ergonomics. Se Cosmos quiser uma API `Tip`-shaped, pode wrap `TipKit.Tip` diretamente (SwiftUI é domínio Cosmos). Não é deliverable Nebula.

## UNVERIFIED (não citar como fato)
- `Product.PurchaseOption.autoRenewableFamilyDiscount` — confirmado ausente.
- `AppIntentResult`/`SnippetGroup`/`Tips.DisplayRule`/`Tips.Group`/`Tips.reloadData()`/`Tips.showAllTips()`/`Tips.dismissAllTips()`/`ActivityKitAuthorizationInfo`/`Activity.dismiss()`/`Activity.activityHandleUpdates`/`database(withPublicScope:)` — **todos NÃO existem**; nomes corrigidos acima.
- `ClosedRange<Date>` como generic parameter de `Activity<Attributes>` — **inválido** (`ClosedRange<Date>` não conforma `ActivityAttributes`); o range vive dentro de um struct attributes custom.
- "No public CloudKit database on watchOS" — **UNVERIFIED da `.swiftinterface`** (sem `API_UNAVAILABLE(watchos)` marker; qualquer restrição é runtime/entitlement, não em headers).
- `CKContainer.ApplicationPermissionStatus`/`ApplicationPermissions` Sendable-ness — **UNVERIFIED** da `.swiftinterface` (NS_ENUM/NS_OPTIONS — tipicamente Sendable via synthesis, não mostrado na interface).

## Sources
- WWDC21 "Meet StoreKit testing"; WWDC22 "What's new in StoreKit 2"; WWDC23 "Meet StoreKit for SwiftUI"
- WWDC23 "Discover TipKit"
- WWDC22 "Meet AppIntents"; WWDC24 "Bring your app to Siri with App Intents"
- WWDC22 "Meet ActivityKit"; WWDC23 "What's new in ActivityKit"
- WWDC22 "Meet CKSyncEngine"; WWDC23 "What's new in CloudKit"
- Nebula port idiom reference: `Sources/Nebula/Architecture/Gateway/NebulaGateway.swift`, `NebulaGatewayConfig.swift`, `Sources/Nebula/Architecture/Errors/NebulaFailure.swift`
- Closed `NebulaError.Kind` cases: `Sources/Nebula/Errors/NebulaError.swift` (L59–73: `network`/`decoding`/`encoding`/`cocoa`/`file`/`validation`/`serialization`/`unknown`)
- Sibling-package precedent (Aurora/Meridian): `ARCHITECTURE.md` (L57–65, L196–219)
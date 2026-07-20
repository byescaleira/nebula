---
tags: [nebula, architecture, errors, environment, feature-flags, swift]
aliases: [nebula user error, NebulaUserError, NebulaEnvironment, NebulaFeatureFlags, NebulaLocalFeatureFlags, RecoverableError, nebula environment, nebula feature flags]
related: [[nebula-app-readiness-research]], [[nebula-errors]], [[nebula-error-taxonomy-toolkit]], [[nebula-preferences]]
status: researched
researched: "2026-07-19"
---

# Nebula — User-error presentation + environment + feature flags

> Research depth for the errors/env/flags dimension of [[nebula-app-readiness-research]]. Verified against `Foundation.swiftmodule/arm64e-apple-ios.swiftinterface` (Xcode 27 Beta 3) + `swiftc -typecheck -swift-version 6` compile tests. UNVERIFIED items flagged inline.

> **User-error dimension (a) SHIPPED — Wave N12 / 0.9.0 (2026-07-20) → [[nebula-user-error]]. Environment dimension (b) SHIPPED — Wave N13 / 0.10.0 (2026-07-20) → [[nebula-environment]]. Feature flags dimension (c) SHIPPED — Wave N14 / 0.11.0 (2026-07-20) → [[nebula-feature-flags]].** All three dimensions shipped.

## Dimension overview

**(a) User-facing error presentation.** Apple's Foundation error model é two-layer: um *developer-facing* `Error` value bridged para `NSError`, e um *user-facing* surface via `LocalizedError` (quatro strings opcionais) + `RecoverableError` (option list + attempt callbacks). **Não existe Apple "user-error value type"** — `LocalizedError` É o port, e a *presentation* (alert/sheet/button copy) é UI-tier (AppKit `presentError`/UIKit `UIAlertController`/SwiftUI alert), nunca Foundation. HIG prescreve tom (neutral, non-accusatory, sem "you/your/we"), recovery verbs actionable, e "what happened / why / how to proceed" como as três respostas required.

**(b) Environment configuration.** **Não existe API Apple-native "environment"** — verified por grep `F` por `struct/enum/class Environment` (zero hits). Apple's pattern é pure build-config convention: `.xcconfig` → `$(VAR)` substitution em `Info.plist` → runtime read via `Bundle.main.object(forInfoDictionaryKey:)`/`infoDictionary`, com `#if DEBUG` e per-scheme build configurations. Isto é app-target work; uma library só pode contribuir um typed value + um reading pattern.

**(c) Feature flags.** **Não existe API Apple-native remote-config ou feature-flag** — verified por grep `F` por `FeatureFlag`/`RemoteConfig`/`RolloutConfig` (zero hits). Apple's único primitive nativo é `UserDefaults` (local) + `#if DEBUG`/compiler `hasFeature()` (build-time). Remote flags requerem um backend que o app fornece; `dependencies: []` proíbe Firebase/LaunchDarkly, logo um remote flag Nebula é necessariamente um *port* que o app conforma.

## Apple-native APIs + best-practice pattern

### (a) User-facing error presentation
- `LocalizedError` protocol — `F:7281`, `@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)` (abaixo floor `.v26` → sem gate). Quatro string reqs opcionais: `errorDescription`/`failureReason`/`recoverySuggestion`/`helpAnchor` (`F:7282-7285`). Default ext retorna `nil` para todos (`F:7288-7301`). `NebulaError` já conforma e mapeia `message`→`errorDescription`, `recoverySuggestions.joined(" ")`→`recoverySuggestion`.
- `CustomNSError` protocol — `F:7303`, mesma availability. `errorDomain`/`errorCode`/`errorUserInfo`. `NebulaError` já conforma; `errorUserInfo` popula `NSLocalizedDescriptionKey`/`NSLocalizedFailureReasonErrorKey`/`NSLocalizedRecoverySuggestionErrorKey`/`NSHelpAnchorErrorKey` (`NebulaError.swift:178-188`).
- `RecoverableError` protocol — `F:17001`, mesma availability. Reqs: `recoveryOptions: [String]`, `attemptRecovery(optionIndex:)` (sync, retorna Bool), `attemptRecovery(optionIndex:resultHandler:)` (async, `@escaping`). Default ext provê o async variant (`F:17010-17012`). É a surface Apple-blessed "user-facing recovery action", mas é **closure-based, não value-based** — não existe `RecoveryAction` enum.
- `recoveryAttempterErrorKey` — `F:17258` (`static let` em `ErrorUserInfoKey`, que é `Sendable` — `F:17128`). Bridge um `RecoverableError` para `NSError`'s `NSRecoveryAttempterErrorKey` para AppKit's `presentError` machinery invocar.
- `CocoaError` struct — `F:7226` (`_BridgedStoredNSError`); `Code` é `RawRepresentable, Hashable, Sendable` (`F:7254-7259`). `URLError` struct — `F:21417`; `Code` é `Sendable` (`F:21425`). `NebulaError.Kind` já mapeia via `coarseKind`.
- **`RecoveryURL` NÃO é API pública Apple.** Verified: zero hits em `Foundation.swiftinterface` (iOS + macOS) e `AppKit.swiftinterface`. Únicas ocorrências no SDK são o symbol privado `_PKErrorRecoveryURLKey` em `PassKit.tbd`/`FinanceKit.tbd`. A premise "AppKit/macOS only" está **UNVERIFIED — não citar como fato**; trate `RecoveryURL` como não-existente para planning Nebula. Os primitives públicos são `RecoverableError` + `recoveryAttempterErrorKey`.
- **`presentError` (AppKit `NSResponder.presentError`/`NSApplication.presentError`)** é o macOS-only recovery UI host. NÃO localizado em `AppKit.swiftinterface` via grep (UNVERIFIED line number) — mas é unambiguously UI-tier (AppKit), out of Nebula scope regardless. UIKit não tem `presentError` equivalent (verified: zero `presentError` hits em `UIKit.swiftinterface`); apps iOS presentam `UIAlertController` eles mesmos.
- **HIG best practice (cited):**
  - "Avoid sounding accusatory, judgmental, or insulting"; evite pronomes `you/your/me/my/we` — Apple HIG *Writing*/*Alerts*.
  - Um bom alert responde: **what happened? why are you seeing this? how should you proceed?** — WWDC17 "Writing Great Alerts" (813).
  - Button titles são verbs que relate à action ("Reply"/"Ignore"/"Erase"); sempre forneça Cancel para destructive actions — HIG *Alerts*.
  - Display errors o mais perto do problema possível (inline), nem sempre modal alert — WWDC17/813.
  - Tone modulation: em errors, dial up **clarity + helpfulness**, dial back **friendliness** — WWDC24 "Add personality to your app through UX writing" (10140).
- **Sem WWDC dedicado "Foundation error improvements".** Os error protocols originam de **SE-0112 "Improved NSError Bridging"** (Swift 3, 2016), não um WWDC talk. WWDC21 "What's new in Foundation" (10109) cobriu `AttributedString`/formatters/grammar agreement, não errors. Flag: qualquer citação "WWDC Foundation errors" é **UNVERIFIED — não citar como fato**.

### (b) Environment configuration
- `Bundle.main.infoDictionary` (`[String: Any]`) e `Bundle.main.object(forInfoDictionaryKey:)` (`Any?`) — Clang-imported de `NSBundle.h`, não em `F`; verified callable via `swiftc -typecheck` (compila clean Swift 6). `Bundle` é **Sendable** (compile-verified: `struct S: Sendable { let b: Bundle }` typechecks).
- `ProcessInfo.processInfo.environment` (`[String: String]`) e `.arguments` (`[String]`) — Clang-imported; `ProcessInfo` é **Sendable** (compile-verified).
- `#if DEBUG` — Swift compiler conditional, driven pelo `DEBUG` define set per build configuration (Xcode ships `DEBUG=1` em Debug). Build-time only.
- `.xcconfig` + `$(VAR)` Info.plist substitution + per-scheme build configurations — Xcode build system, não SDK API. Canonical: NSHipster "Xcode Build Configuration Files"; thoughtbot "Let's Set Up Your iOS Environments".
- **Sem API Apple-native "environment"** — verified por zero `struct/enum/class Environment` hits em `F`. O pattern é 100% build-config convention; Nebula só pode ship um value type + o read pattern.

### (c) Feature flags
- `UserDefaults` — local flag store; **NÃO Sendable** em Swift 6 (`@_nonSendable(_assumed)`, `NSUserDefaults.h:144`; compile-verified: `struct S: Sendable { let d: UserDefaults }` errors). Já wrapped por `NebulaDefaults` (`Mutex<UserDefaults>` dentro `final class`).
- `#if DEBUG`/`hasFeature(...)`/`-enable-upcoming-feature` — build-time/compiler-time only.
- **Sem API Apple-native remote-config/feature-flag/rollout** — verified por zero `FeatureFlag`/`RemoteConfig`/`RolloutConfig` hits em `F`. Qualquer remote backend é app-supplied.
- Best-practice pattern (community, não Apple): type-safe `Feature` protocol (`RawRepresentable` string keys), priority-ordered sources (local overrides > remote > built-in defaults), `Mutex`-guarded resolver, `UserDefaults`-backed persistent overrides, rollout-% + audience targeting computed pelo backend (Nebula evals localmente num fetched value). Sources: Livsy Code "A Feature Flags System in Swift"; Statsig "iOS feature flags: Swift patterns".

## Sendability & availability

| API | Sendable? | Floor | Gate? |
|---|---|---|---|
| `LocalizedError`/`CustomNSError`/`RecoverableError` | protocol (no conformance implication) | iOS 8/macOS 10.10 (`F:7280`/`7302`/`17000`) | Não (abaixo `.v26`) |
| `CocoaError`/`URLError` | `Code` Sendable; structs `_BridgedStoredNSError` (wrap `NSError`, não Sendable como values) | iOS 8/macOS 10.10 | Não |
| `ErrorUserInfoKey`/`recoveryAttempterErrorKey` | `Sendable` (`F:17128`/`17258`) | iOS 8/macOS 10.10 | Não |
| `RecoveryURL` | n/a — **NÃO é API pública** | n/a | n/a |
| `Bundle`/`Bundle.main` | **Sendable** (compile-verified) | iOS 4/macOS 10.0 | Não — `infoDictionary` retorna `[String: Any]` (os `Any` NÃO Sendable; cast para `String`/`Bool`/`Int` antes de cruzar isolamento) |
| `ProcessInfo`/`.processInfo` | **Sendable** (compile-verified) | iOS 4/macOS 10.0 | Não — `.environment` `[String: String]` Sendable; `.arguments` `[String]` Sendable |
| `UserDefaults` | **NÃO Sendable** (`@_nonSendable(_assumed)`, `NSUserDefaults.h:144`) | iOS 4/macOS 10.0 | Não — já wrapped por `NebulaDefaults` |
| `URLSessionConfiguration` | **Sendable** (compile-verified) | iOS 7/macOS 10.9 | Não |
| `JSONEncoder`/`JSONDecoder` | **Sendable** (compile-verified) | iOS 7/macOS 10.9 | Não |
| `Mutex<T>`/`Atomic<T>` (`Synchronization`) | `~Copyable`, `@_staticExclusiveOnly` | iOS 18/macOS 15 (abaixo `.v26`) | Não — `let` only; `final class` absorve `~Copyable` |

Todos floors abaixo do baseline `.v26` → **sem `@available` gates** para qualquer destas surfaces.

## Nebula-scope verdict

| Surface | Veredito | Rationale | Tensão |
|---|---|---|---|
| `NebulaError` adopting `RecoverableError` | **Defer** | `RecoverableError` é closure-based (`attemptRecovery` callbacks), não value — bakes UI/timing no error value; `NebulaError` fica pure value | Nenhuma — opt-in conformance é decisão app/cosmos; closures cruzando isolamento precisam `@Sendable` handler |
| `NebulaUserError` value (user-facing message + `RecoveryAction` enum) | **Port (value-mapping, app supplies strings)** | Foundation-tier value que app/Cosmos render; default mapping `coarseKind`→message, overridable, para enable L10n via `String(localized:)` no app layer | "Port + config" idiom; **sem novos `NebulaError.Kind` cases** (mapping only) |
| `NebulaErrorPresenter` port | **Cosmos-only** | Presentation (alert/sheet/button copy) é UI; Nebula não own UI | Foundation-only rule; Cosmos é o sibling SwiftUI que render |
| `NebulaError` → `NebulaUserError` mapper | **Config (`.withUserMessageMap`)** | `@Sendable (NebulaError.Kind, [String: String]) -> NebulaUserError?` em `NebulaErrorConfiguration`, default `{ _ in nil }` | `NebulaErrorConfiguration` é Sendable-not-Equatable (handler closure); espelha Cosmos |
| `NebulaEnvironment` value (dev/staging/prod + base URLs + flag overrides) | **✅ SHIPPED 0.10.0 — Port (value type)** | Sendable enum + struct que o app constrói de `Bundle.main.object(forInfoDictionaryKey:)`; Nebula ship o shape + o read pattern, não o `.xcconfig` wiring → [[nebula-environment]] | `Bundle` é Sendable mas `infoDictionary`'s `Any` values não são — mapper deve cast para `String`/`Bool`/`Int` antes de store no Sendable value |
| `NebulaEnvironment` reader façade sobre `Bundle.main` | **Façade (optional, skip)** | `final class` (ou static funcs) wrap `Bundle.main` reads é desnecessário — `Bundle` já é Sendable, um pure value builder basta; ship o builder, skip a façade | Evite `final class` quando um value type funciona (house idiom: prefira value types) |
| `NebulaFeatureFlags` local impl (bool/string/number, `Mutex`-backed map) | **✅ SHIPPED 0.11.0 — Port + Façade** | Sendable `NebulaFeatureFlags` protocol (port) + `NebulaLocalFeatureFlags` `final class` wrap `Mutex<[String: NebulaFlagValue]>` (façade). `NebulaDefaults`-backed persistence **deferred** (in-memory only in N14) → [[nebula-feature-flags]] | `Mutex` é `~Copyable` → `final class` absorve (precedente NebulaDefaults); `NebulaFlagValue` enum é `Sendable` (derived, no `@unchecked`); store é Sendable value → init **no `sending`** (difere do `NebulaDefaults` `UserDefaults`) |
| `NebulaRemoteFeatureFlags` port (app supplies fetcher) | **✅ SHIPPED 0.11.0 — Port** | `dependencies: []` proíbe Firebase/LaunchDarkly; `NebulaRemoteFeatureFlags: NebulaFeatureFlags` adds `refresh() async throws` (app conforma com seu backend) → [[nebula-feature-flags]] | `refresh() async throws` (devia do research non-throwing — honest sobre fetch failure; composite nunca chama refresh); rollout-%/audience targeting computed pelo backend, Nebula evals localmente no fetched value |
| `NebulaFeatureFlags` SwiftUI `@Environment` injection / `@Observable` manager | **Cosmos-only** | Nebula não tem SwiftUI; injection vive em Cosmos | Foundation-only rule |
| `.xcconfig`/scheme/Info.plist wiring | **App-only** | Build-config é app-target work; library não tem app target | Nenhuma — out of scope by definition |
| `RecoveryURL` support | **Defer (não é API real)** | `RecoveryURL` não é API pública Apple (só symbol privado PassKit); nada para suportar | NÃO implementar — seria inventar surface non-Apple |
| `NebulaDefaults`-backed flag overrides | **Façade (já existe)** | `NebulaDefaults` é a façade `Mutex<UserDefaults>`; flag overrides reusam via `NebulaPreferences` default ext | Reuse, não re-wrap |

## Recommended waves

- **N12 — User-error bridge.** `NebulaUserError` value (Sendable struct: `message: String`, `recoveryActions: [RecoveryAction]`, `helpAnchor: String?`) + `RecoveryAction` enum (`.retry`/`.cancel`/`.dismiss`/`.custom(String)`); `NebulaErrorConfiguration.withUserMessageMap(@Sendable (Kind, [String: String]) -> NebulaUserError?)` default `{ _ in nil }`; default `coarseKind`→message table (English, overridable). Deps: toolkit (`NebulaFailure`/`NebulaError`). Tensão: mapping only, **sem novos `Kind` cases**. **✅ SHIPPED 0.9.0 (2026-07-20) → [[nebula-user-error]].**
- **N13 — Environment value + reader pattern.** `NebulaEnvironment` Sendable enum (`.development`/`.staging`/`.production`) + `NebulaEnvironmentConfiguration` struct (`environment`/`baseURLs: [NebulaEnvironment: URL]`/`overrides: [String: String]`) + `NebulaEnvironmentConfig` accessor; `NebulaEnvironment.fromBundle(_:Bundle)` builder que cast `infoDictionary` `Any` value para `String` antes de store (safe-fail-to-production); doc pattern `.xcconfig`→`Info.plist`→`fromBundle`. Deps: nenhum (Foundation-only). Tensão: ship o value + pattern, não o `.xcconfig` wiring (app-tier). **✅ SHIPPED 0.10.0 (2026-07-20) → [[nebula-environment]].**
- **N14 — Feature flags port + local impl.** `NebulaFeatureFlags` Sendable protocol (`bool(forKey:)`/`string(forKey:)`/`number(forKey:)`/`json(_:forKey:)`); `NebulaLocalFeatureFlags` `final class` (`Mutex<[String: NebulaFlagValue]>`, `NebulaFlagValue` Sendable enum); `NebulaRemoteFeatureFlags` port (`@Sendable func refresh() async`, `func value(forKey:) -> NebulaFlagValue?`); `NebulaCompositeFeatureFlags` (local overrides > remote > built-in defaults, priority-ordered). Deps: N2 (`NebulaDefaults`/`NebulaPreferences`) para persistent overrides. Tensão: `Mutex` `~Copyable` → `final class` (precedente NebulaDefaults); remote backend app-supplied (`dependencies: []`). **✅ SHIPPED 0.11.0 (2026-07-20) → [[nebula-feature-flags]].**

## Key findings & flags
- **`RecoveryURL` não é API pública Apple** — só o privado `_PKErrorRecoveryURLKey` em `PassKit.tbd`/`FinanceKit.tbd`. NÃO designar surface Nebula em torno dele. Qualquer claim "AppKit `RecoveryURL`" de fontes secundárias é **UNVERIFIED — não citar como fato**.
- **Sem WWDC dedicado "Foundation error improvements"** — os error protocols vêm de SE-0112 (Swift 3, 2016), não um WWDC talk. **UNVERIFIED — não citar como fato** uma WWDC session específica para error-protocol improvements.
- **`presentError` (AppKit) line number UNVERIFIED** — grep zero hits em `AppKit.swiftinterface`; a API é UI-tier regardless, não afeta nenhum veredito Nebula.
- **`ProcessInfo` e `Bundle` SÃO Sendable** no Xcode 27 Beta 3 SDK (compile-verified `-swift-version 6`); `UserDefaults` NÃO (`@_nonSendable(_assumed)`, `NSUserDefaults.h:144`). Logo `NebulaEnvironment.fromBundle(_:)` não precisa `Mutex` para o `Bundle` read — só os `Any` values retornados devem ser cast para Sendable leaf types antes de cruzar isolamento.
- **Sem API Apple-native environment ou feature-flag** — ambos são build-config convention (env) e community/backend pattern (flags). O role Nebula é value type + port + façade, nunca o wiring ou o remote backend.

## Sources
- Apple HIG — Alerts — https://developer.apple.com/design/human-interface-guidelines/alerts
- Apple HIG — Writing — https://developer.apple.com/design/human-interface-guidelines/writing
- WWDC17 813 "Writing Great Alerts" — https://developer.apple.com/videos/play/wwdc2017/813/
- WWDC24 10140 "Add personality to your app through UX writing" — https://developer.apple.com/videos/play/wwdc2024/10140/
- SE-0112 "Improved NSError Bridging" — https://github.com/swiftlang/swift-evolution/blob/main/proposals/0112-nserror-bridging.md
- NSHipster — LocalizedError/RecoverableError/CustomNSError — https://nshipster.com/swift-foundation-error-protocols/
- NSHipster — Xcode Build Configuration Files — https://nshipster.com/xcconfig/
- Livsy Code — "A Feature Flags System in Swift" — https://livsycode.com/best-practices/a-feature-flags-system-in-swift/
- Statsig — "iOS feature flags: Swift patterns" — https://www.statsig.com/perspectives/ios-feature-flags-swift-patterns
---
tags: [nebula, architecture, observability, metrickit, logging, swift]
aliases: [nebula metrickit, NebulaMetrics, MetricManager, MXMetricManager, NebulaDiagnosticSnapshot, nebula observability, nebula crash]
related: [[nebula-app-readiness-research]], [[nebula-logging]]
status: researched
researched: "2026-07-19"
---

# Nebula — MetricKit observability + iOS log export + crash

> Research depth for the observability dimension of [[nebula-app-readiness-research]]. Verified against `MetricKit.framework/Headers/MXMetricManager.h` + `MetricKit.swiftmodule/arm64e-apple-ios.swiftinterface` (Xcode 27 Beta 3). UNVERIFIED items flagged inline.

## Dimension overview

Apple tem **três pilares nativos** de observability production: (a) **MetricKit** para aggregated perf/crash/hang diagnostics delivered na *próxima* launch, (b) **os.Logger/OSSignposter** para live system logging que o app **NÃO consegue ler de volta no iOS** (sandbox bloqueia `OSLogStore`), e (c) um **in-app ring buffer** para user-initiated export — que Nebula já ship como `NebulaMemoryLogHandler`. Apple **não ship native real-time crash reporter**; `MXCrashDiagnostic`/`CrashDiagnostic` é o path first-party dependencies-free, com SDKs third-party (Crashlytics/Bugsnag) para real-time upload — proibido por `dependencies: []`.

## Apple-native APIs + best-practice pattern

**DUAS gerações de API MetricKit coexistem no Xcode 27 Beta 3 SDK:**

- **Legacy `MXMetricManager` (Obj-C, iOS 13+/macOS 12+)** — `MXMetricManager.h`:
  - `MXMetricManager.sharedManager` (L51), `API_DEPRECATED("Use MetricManager instead.", ios(13.0, ...)) API_UNAVAILABLE(tvos, watchos)`.
  - `addSubscriber:`/`removeSubscriber:` (L68/76), mesma deprecation + `API_UNAVAILABLE(tvos, watchos)`.
  - `MXMetricManagerSubscriber` protocol (L109–110): `didReceiveMetricPayloads:` (L124, ~daily) + `didReceiveDiagnosticPayloads:` (L136, crash/hang/cpu-exception/disk-write). Ambos `API_UNAVAILABLE(tvos, watchos)`.
  - Não no `.swiftinterface` (ClangImporter); **não Sendable** (NSObject reference, callback em system queue).
  - WWDC20 "What's new in MetricKit" (10081), WWDC21 "Diagnose crashes with MetricKit" (10181).

- **New `MetricManager` (Swift-first, iOS 27/macOS 27/visionOS 27)** — `MetricKit.swiftmodule`:
  - `final public class MetricManager : @unchecked Swift::Sendable` (L1192). **Apple mesmo usa `@unchecked Sendable`** (class wrapping state interno Apple).
  - `var metricReports: some AsyncSequence<MetricReport, Swift::Never>` (L1197). **Failure `Never` — sem throws.**
  - `var diagnosticReports: some AsyncSequence<DiagnosticReport, Swift::Never>` (L1200).
  - `init()` / `init(enabledStateReportingDomains:)` (L1203/1208).
  - `static func logHandle(category:) -> os.OSLog` (L1241) — ponto de integração signpost.
  - `@MainActor trackLaunchTask(...)` (L1257) — tensão com regra no-global-actor do Nebula.
  - Todos report value types `Sendable + Codable`: `MetricReport` (L1028), `DiagnosticReport` (L198), `CrashDiagnostic` (L48), `HangDiagnostic` (L109), `CPUExceptionDiagnostic` (L33), `DiskWriteExceptionDiagnostic` (L95), `MemoryExceptionDiagnostic` (L126, **iOS-only** — `@available(macOS, unavailable) ... visionOS, unavailable`), `CallStackTree` (L134), `CallStackThread`/`CallStackFrame` (L166/180), `DiagnosticResult` (L236), `SignpostRecord` (L254).
  - Availability: `@available(iOS 27.0, macOS 27.0, macCatalyst 27.0, visionOS 27.0, *) @available(tvOS, unavailable) @available(watchOS, unavailable)` (L1189–1191). WWDC26 222 "Meet the new MetricKit".

- **Signpost auto-consumption** — `MXSignpostMetric.h:21-22`: signposts são aggregated **só se emitidos via o MetricKit log handle** (`MXMetricManager.makeLogHandle(category:)` legacy / `MetricManager.logHandle(category:)` new), NÃO via plain `os.Logger`/`os.OSSignposter`. Logo `NebulaSignposter` (wraps `os.OSSignposter`) é **Instruments-only**; NÃO alimenta payloads MetricKit a menos que o consumer opt-in pelo MetricKit log handle.

- **iOS log export reality** — verified via Apple DTS (Quinn "The Eskimo"):
  - `OSLogStore(scope: .system)` é macOS-only E falha dentro App Sandbox (`Connection to logd failed`).
  - No iOS, `OSLogStore` foi removido tarde no iOS 14 beta; só `.currentProcessIdentifier` scope funciona iOS 15+, e **não consegue ler logs de uma instância anterior do app** (pid mudou).
  - Apple DTS confirmou: *"No, sadly, there's no solution for your combination of requirements"* para sandboxed apps ler seus próprios prior-run logs; bug **r. 57880434** aberto.
  - Workaround recomendado: **implementar sua própria log persistence** (ring buffer) — exatamente o que `NebulaMemoryLogHandler` já é.

- **Crash reporting** — Apple não ship native crash-reporter SDK; `MXCrashDiagnostic`/`CrashDiagnostic` (delivered next launch via MetricKit) é o path first-party. Real-time upload requer third-party (Crashlytics/Bugsnap/Sentry) — proibido por `dependencies: []`.

**Best-practice pattern (WWDC20/21/26):**
1. Subscribe no app startup; mantenha subscriber/`MetricManager` vivo pelo lifetime do processo.
2. Snapshot o payload incoming num **Sendable value** imediatamente no callback queue (legacy) ou itere o `AsyncSequence` (new).
3. Forward para seu backend — **upload é job do app**, não da library.
4. Use Xcode *Debug > Simulate Metric Payloads* para verificar wiring.
5. Para log export no iOS, mantenha in-app ring buffer; não tente `OSLogStore` reads.

## Sendability & availability

| API | Sendable? | Floor | Gate? |
|---|---|---|---|
| `MXMetricManager` (legacy) | Não (NSObject) | iOS 13/macOS 12/**tvOS unavailable**/**watchOS unavailable**/visionOS UNVERIFIED | Sim — `#if !os(tvOS) && !os(watchos)` + `@available(iOS 13, macOS 12, *)` |
| `MXMetricManagerSubscriber` (legacy) | Não (Obj-C protocol) | mesmo | Sim |
| `MXMetricPayload`/`MXDiagnosticPayload`/`MXCrashDiagnostic` (legacy) | Não (NSObject) | iOS 13/14/macOS 12/tvOS unavailable/watchOS unavailable | Sim |
| `MetricManager` (new) | `@unchecked Sendable` (Apple-authored) | iOS 27/macOS 27/**tvOS unavailable**/**watchOS unavailable**/visionOS 27 | Sim — `@available(iOS 27, macOS 27, visionOS 27, *)` + `#if swift(>=6.4)` + tvOS/watchOS unavailable |
| `MetricReport`/`DiagnosticReport` (new) | `Sendable + Codable` (derived) | iOS 27/macOS 27/tvOS unavail/watchOS unavail/visionOS 27 | mesmo |
| `CrashDiagnostic`/`HangDiagnostic`/`CPUExceptionDiagnostic`/`DiskWriteExceptionDiagnostic`/`CallStackTree` (new) | `Sendable + Codable` | mesmo | mesmo |
| `MemoryExceptionDiagnostic` (new) | `Sendable + Codable` | **iOS 27 only** (macOS/tvOS/watchOS/visionOS/macCatalyst unavailable) | `@available(iOS 27, *)` + iOS-only gate |
| `MetricManager.logHandle(category:)` (new) | Retorna `os.OSLog` (Sendable) | iOS 27/macOS 27/visionOS 27/tvOS unavail/watchOS unavail | mesmo |
| `MetricManager.trackLaunchTask` (new) | `@MainActor` | iOS 27/macOS 27/visionOS 27/tvOS unavail/watchOS unavail | mesmo + `@MainActor` (tensão no-global-actor) |
| `OSLogStore` (os.log) | N/A | iOS 15 (`.currentProcessIdentifier` only)/macOS 10.15+/tvOS 15?/watchOS?/visionOS? | Sim |
| `NebulaMemoryLogHandler` (shipped) | `final class @unchecked Sendable` (Mutex-guarded) | 5 plataformas (.v26) | Nenhuma |

**Fato framework-level (verified):** `MetricKit.framework` **NÃO existe** em `WatchOS.platform/.../WatchOS27.0.sdk/System/Library/Frameworks/`. Existe em tvOS mas toda API subscriber/manager é `API_UNAVAILABLE(tvos, watchos)`. Logo **MetricKit é efetivamente iOS/macOS/visionOS-only** para o requirement 5-platform do Nebula.

## Nebula-scope verdict

| Surface | Veredito | Rationale | Tensão |
|---|---|---|---|
| `NebulaMetrics` façade sobre new `MetricManager` (iOS 27+) | **Façade (N16)** | API Swift-first clean, reports `Sendable+Codable`, ideal AsyncSequence — mas iOS 27-only + tvOS/watchOS unavailable → acima floor `.v26`, precisa `#if swift(>=6.4)` + platform gates | 5-platform (tvOS/watchOS unavailable); above-floor gating ok per CLAUDE.md |
| `NebulaMetrics` façade sobre legacy `MXMetricManager` (iOS 13+) | **Defer** | Deprecated por Apple, Obj-C não-Sendable, `API_UNAVAILABLE(tvos, watchos)` → 2 de 5 plataformas no-op | `@unchecked Sendable` em tipo Nebula — CLAUDE.md proíbe; `NebulaMemoryLogHandler` já é a exceção existente. **Recomenda (b): defer legacy, só wrap o new `MetricManager`** (que é `@unchecked` authored-by-Apple) |
| `NebulaDiagnosticSnapshot` Sendable value (codable mirror) | **Port (N16)** | Desacopla handler API Nebula dos tipos report Apple; `Codable` round-trips já existem nos new types | Nenhuma — pure Nebula value, derived Sendable |
| `NebulaMetricsConfiguration` (port + config + `Mutex<NebulaMetricsConfig>` + `@Sendable` handler) | **Config (N16)** | House idiom: `@Sendable (NebulaDiagnosticSnapshot) -> Void` handler espelha `NebulaErrorConfiguration.handler`; app owns upload | Nenhuma |
| Bridge legacy `MXMetricManagerSubscriber` → `@Sendable` handler | **Defer** | `final class @unchecked Sendable` subscriber sobre `Mutex` + handler espelha `NebulaMemoryLogHandler`; mas author novo `@unchecked` Nebula type — **preferir (b): só wrap new `MetricManager`** | `@unchecked Sendable` em tipo Nebula (proibido) |
| `NebulaLogStoreExporter` re-scope for iOS | **Defer (confirmar morto)** | iOS sandbox bloqueia `.system`; `.currentProcessIdentifier` não lê prior-run logs; Apple DTS "no solution." Sem surface iOS para export | Nenhuma — já deferred; pesquisa confirma |
| Extend `NebulaMemoryLogHandler` para user-initiated export (`.snapshot()` + Codable) | **Port (already-shipped, minor — N16.1)** | `snapshot()` já existe; add `export()` retornando `Data` via `JSONEncoder` para user-initiated diagnostics export. **ESTE é o answer de iOS log-export** | Nenhuma — pure Nebula, 5 plataformas |
| `NebulaSignposter` → MetricKit signpost aggregation | **Doc-only (no code)** | MetricKit só agrega signposts via `MetricManager.logHandle(category:)`, NÃO plain `os.OSSignposter`. `NebulaSignposter` é Instruments-only by design. Documentar; não auto-wire | Nenhuma |
| Real-time crash reporting (Crashlytics/Bugsnag) | **App-only** | `dependencies: []` proíbe third-party; MetricKit é next-launch only. Documentar como responsabilidade de integração do app | `dependencies: []` |
| `StateReporting` framework integration (new, iOS 27) | **Defer (post-N16)** | Framework separado (`import StateReporting`); `@ReportableMetadata` macro + `StateReportingDomain`; iOS 27 only, tvOS/watchOS unavailable. Eval depois do core N16 | Above-floor; macro dependency; 5-platform |

## Recommended waves

- **N16 — MetricKit observability (port + config + façade).** `NebulaDiagnosticSnapshot` Sendable Codable value (crash/hang/cpu/disk-write/memory variants) + `NebulaMetricsConfiguration` (Sendable struct + `@Sendable` handler + `.with*` + `Mutex<NebulaMetricsConfig>` accessor) + `NebulaMetrics` façade sobre o new `MetricManager` gated `@available(iOS 27, macOS 27, visionOS 27, *)` + `#if !os(tvOS) && !os(watchos)` (e `#if swift(>=6.4)` para o SDK 27). A façade itera `metricReports`/`diagnosticReports` `AsyncSequence<_, Never>` e forward snapshots ao handler. **Sem legacy `MXMetricManager` wrapper** — evita author novo `@unchecked Sendable` Nebula type; os reports do new API já são `Sendable+Codable`. Deps: nenhum (MetricKit é system framework). Documentar: real-time crash reporting + tvOS/watchOS no-op + signpost-via-`logHandle(category:)` são concern do app.
- **N16.1 — In-app log export polish.** `NebulaMemoryLogHandler.export()` (Codable `Data` sobre `snapshot()`) — o answer de iOS log-export. Tiny, 5 plataformas. Deps: nenhum.
- **N?? — StateReporting integration (eval later).** `StateReportingDomain` + `@ReportableMetadata` macro + per-state metric aggregation, iOS 27-only. Deps: N16 landed; eval se uma foundation library deve own app-state taxonomy (provável **App-only**).

## UNVERIFIED (não citar como fato)
- Legacy `MXMetricManager` availability em **visionOS** — headers Obj-C só marcam `API_UNAVAILABLE(tvos, watchos)` sem annotation visionOS; a swiftinterface não contém os legacy types. Moot se N16 wrap só o new `MetricManager` (explicitamente `visionOS 27.0`).
- `OSLogStore` availability em tvOS/watchOS/visionOS — não checado; a story sandbox-block é macOS+iOS-confirmada only.
- WWDC22 MetricKit session content — não fetched separadamente; WWDC20/21/26 cobrem a API surface.

## Sources
- WWDC20 10081 "What's new in MetricKit" — https://developer.apple.com/videos/play/wwdc2020/10081/
- WWDC21 10181 "Diagnose crashes with MetricKit" — https://developer.apple.com/videos/play/wwdc2021/10181/
- WWDC26 222 "Meet the new MetricKit"
- Apple Forums thread 744806 (OSLogStore iOS sandbox) — https://developer.apple.com/forums/thread/744806
- mjtsai.com — OSLogStore on Monterey — https://mjtsai.com/blog/2021/12/10/oslogstore-on-monterey/
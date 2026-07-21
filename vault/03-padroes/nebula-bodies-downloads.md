---
tags: [nebula, architecture, network, bodies, multipart, download, pagination, transport, swift, concurrency, sendable, urlsession, urlsessiondownloadtask, urlcomponents]
aliases: [nebula bodies downloads, NebulaMultipartBuilder, NebulaMultipartPart, NebulaMultipartFormData, NebulaMultipartError, NebulaDownload, NebulaDownloadHandle, NebulaDownloadDelegate, NebulaDownloadConfiguration, NebulaDownloadError, NebulaPagedSequence, PinnedDownloadSession]
related: [nebula-streaming, nebula-ssl-pinning, nebula-async-flow, nebula-error-taxonomy-toolkit, nebula-clean-architecture-toolkit, nebula-app-readiness-research, nebula-network-hardening]
status: shipped
shipped: "0.16.0 (Wave N17c, 2026-07-21)"
---

# Nebula — Bodies & Downloads (Multipart + Download + Pagination) (shipped)

> Shipped note para a dimensão bodies/downloads do [[nebula-app-readiness-research]] (wave N17c, a terceira e última sub-wave do N17 split — **N17 split completo**: N17a pinning → N17b streaming → N17c bodies/downloads). Source of truth: `Sources/Nebula/Architecture/Network/Bodies/` (5 arquivos) + `Sources/Nebula/Architecture/Async/NebulaPagedSequence.swift` + `Tests/NebulaTests/Architecture{Multipart,Download,PagedSequence}Tests.swift` + `Sources/Nebula/Nebula.docc/ArchitectureBodiesDownloads.md`. Parent research: [[nebula-network-hardening]]. Reusa o pinning do [[nebula-ssl-pinning]] (N17a) via composição/forwarding — **zero mudança no N17a**.

## O que shipou (Nebula 0.16.0)

Três superfícies **aditivas** sobre o gateway HTTP bufferizado existente. O gateway **não foi tocado** (`NebulaHTTPGateway`/`NebulaHTTPClient`/`NebulaHTTPBody`/`NebulaHTTPRequest`/`NebulaHTTPRequestParser` diffs vazios); o pinning do N17a é reusado via composição/forwarding. **908 tests / 178 suites** (up from 869/175 do N17b), zero concurrency warnings.

### Multipart — pure `Data` composer (2 arquivos)

- **`NebulaMultipartPart`** — `Sendable`/`Equatable`/`Hashable` struct: `name: String`, `filename: String?`, `contentType: String?`, `body: Data`. Factory statics `.field(name:value:)` (`Data` + overload `String` UTF-8) / `.file(name:filename:contentType:data:)`. Sendable derived.
- **`NebulaMultipartFormData`** — `Sendable`/`Equatable`/`Hashable` struct (output do `build()`): `data: Data`, `contentType: String` (`"multipart/form-data; boundary=<boundary>"`), `boundary: String`. Sendable derived.
- **`NebulaMultipartBuilder`** — `Sendable`/`Equatable` struct **imutável** (value-type builder): `boundary: String`, `parts: [NebulaMultipartPart]` (ordenado). `init(boundary: String? = nil, parts: [])` — boundary auto-gerada via 16 bytes random hex-encoded sob `boundaryPrefix = "----NebulaBoundary"` (50 chars, dentro do limite 0–70 do RFC 2046 §5.1.1). `adding(_:) -> NebulaMultipartBuilder` (fluent, value semantics — retorna cópia). `build() -> NebulaMultipartFormData` — **pura** (sem `URLSession`, sem `@Sendable` closure, sem I/O): codifica `--<boundary>\r\n` + `Content-Disposition: form-data; name="…"` (com `; filename="…"` para file parts) + `Content-Type: …\r\n` opcional + `\r\n` + body + `\r\n`, fecha com `--<boundary>--\r\n`. Helper local `func append(_ string: String) { data.append(Data(string.utf8)) }` pois `Data` não tem `append(String)`. `file(in directory: URL? = nil) throws -> URL` — escreve o `Data` num temp file (`.atomic`) para `URLSession.upload(for:fromFile:)` (streaming from disk, suitable para large/background uploads); errors → `NebulaMultipartError.ioFailed`.
- **`NebulaMultipartError`** — open-struct mirroring `NebulaSSEError`. `Kind` presets: `build-failed`/`io-failed`/`cancelled`/`unknown`. `coarseKind`: `.network` para build/io, `.unknown` para cancelled/unknown (`default → .unknown`). Domain `"Nebula.NebulaMultipartError"`. Factory statics `buildFailed(_:)`, `ioFailed(_:underlying:)`, `cancelled(_:)`, `unknown(_:underlying:)`. **Nenhum caso novo em `NebulaError.Kind`**.

**Gateway-compatible by design**: o `Data` + content-type built feed o case existente `NebulaHTTPBody.data(_:contentType:)` — **nenhum case novo em `NebulaHTTPBody`**, sem ripple em `NebulaHTTPRequest`/`NebulaHTTPRequestParser`. O `NebulaHTTPGateway` bufferizado carrega unchanged.

### Download — façade sobre `URLSession.download(for:delegate:)` (2 arquivos)

- **`NebulaDownloadConfiguration`** — `Sendable` (**NÃO `Equatable`** — a `destination`/`sleeper` são `@Sendable`, mirror do flavor not-`Equatable` do `NebulaSSEConfiguration`). **Per-call**, não process-wide → **sem accessor `Mutex`** (diferente do logging/measurement/error). Fields: `destination: @Sendable (URL, URLResponse) throws -> URL` (computa o destino — recebe o temp URL + response, e.g. para ler `Content-Disposition`; a façade faz `FileManager.moveItem`), `resume: Bool = true`, `maxResumeAttempts: Int = 3`, `resumeDelay: Duration = .milliseconds(500)`, `sleeper: @Sendable (Duration) async throws -> Void = NebulaRetry.defaultSleep`, `logger: NebulaLogger?`. Fluent `.withDestination/.withResume/.withMaxResumeAttempts/.withResumeDelay/.withSleeper/.withLogger`. `default = .init()`; `defaultDestination` static = `NebulaDownload-<hex>.bin` no temp dir (safe no-op default). `Nebula.md` config list **unchanged**.
- **`NebulaDownloadCompletion`** — `internal final class: Sendable` — state machine race-safe com `private enum State { pending; awaiting(CheckedContinuation<URL, any Error>); resolved(Result<URL, any Error>) }` + `Mutex<State>`. `value()` via `withCheckedThrowingContinuation` (registra/resume); `resolve(_:)` idempotente. Resolve-before-register entrega ao late registrant.
- **`NebulaDownloadHandle`** — `public struct: Sendable`: `progress: AsyncThrowingStream<Double, any Error>` (fração 0.0–1.0), `internal let completion/delegate/loop`, `value() async throws -> URL` (await o moved destination), `cancelByProducingResumeData() async throws -> Data?` (wrapa `task.cancel(byProducingResumeData:)` em `withCheckedContinuation` — **não há form async**). Sendable derived.
- **`NebulaDownloadDelegate`** — `public final class: NSObject, URLSessionDownloadDelegate, Sendable` — o **per-task delegate** (passado a `download(for:delegate:)`). Stored props (todos `let`): `configuration`, `internal progressContinuation`, `internal completion`, `internal downloadTaskBox: Mutex<URLSessionDownloadTask?>` (captura o task para `cancelByProducingResumeData` — a async overlay não expõe o task; um `weak var` quebraria derived Sendable). `init` **internal** (construído por `NebulaDownload`, `@testable` em tests). `didFinishDownloadingTo` (REQUIRED): `response = downloadTask.response ?? URLResponse(…)` (fallback — `response` é `URLResponse?`), move via `FileManager.moveItem` overwrite-safe, resolve success/`moveFailed`. `didWriteData`: guarda `totalBytesExpectedToWrite > 0` (evita divide-by-zero/NaN), yield fração clamp 0–1. `didResumeAtOffset`: no-op informational. `didCompleteWithError`: só captura o task (o loop handle resume-retry/failure). **Sem pinning** — pinning é session-level. **Sendable derived, sem `@unchecked`**.
- **`NebulaDownload`** — `public enum` namespace. `download(for:session:configuration:) -> NebulaDownloadHandle` com **custom retry-with-resume loop** (Task: `var attemptsLeft`/`resumeData`; `try await session.download(for:|resumeFrom:)` ignorando o returned temp URL; success → `finishProgress`; `CancellationError`/`URLError(.cancelled)` → `finishProgress` + `resolve(.failure(CancellationError()))`; outro error → extract `(error as? URLError)?.downloadTaskResumeData`, retry se `resume && resume != nil && attemptsLeft > 0` else resolve `downloadFailed`; `onTermination = { @Sendable _ in loop.cancel() }`). `resume(from:session:configuration:) -> NebulaDownloadHandle`. `pinned(by:sessionConfiguration:configuration:logger:) -> PinnedDownloadSession` cria `NebulaURLSessionDelegate` como **session delegate** (pinning é session-level).
- **`NebulaDownloadError`** — open-struct mirroring `NebulaSSEError`. `Kind` presets: `download-failed`/`move-failed`/`resume-failed`/`cancelled`/`unknown`. `coarseKind`: `.network` para download/move/resume, `.unknown` para cancelled/unknown (`default → .unknown`). Domain `"Nebula.NebulaDownloadError"`. Factory statics. **Nenhum caso novo em `NebulaError.Kind`**.

### Pagination — generic helper (1 arquivo)

- **`NebulaPagedSequence<Page: Sendable>: Sendable`** — derived (constrain `<Page: Sendable>` na declaração, `NebulaResultPipeline<T: Sendable>` precedent, **sem `@unchecked`**). `let first: @Sendable () async throws -> Page`, `let next: @Sendable (Page) async throws -> Page?`. `init(first:next:)`. `stream() -> AsyncThrowingStream<Page, any Error>` com build-closure + Task + `onTermination → loop.cancel()`: `var page = try await first(); yield(page); while let next = try await nextClosure(page) { try Task.checkCancellation(); page = next; yield(page) }; finish()`. `catch is CancellationError { finish(throwing: CancellationError()) }` (N17b: consumer iteration ends normally on cancel; internal finish tears the loop). **Custom loop, NÃO `NebulaRetry.withPolicy`** — cursor mutates per page (SSE `Last-Event-ID` shape; `withPolicy` é nullary). Sem retry (pagination surfaces o erro; retry é concern do app via `withPolicy` around `first`/`next` se desejado). Concrete `AsyncThrowingStream<Page, any Error>` return (CLAUDE.md mandate).

## Ground truth verificado (empírico — Xcode 27.0.0 Beta 3 SDK / Swift 6.4; `.swiftinterface` + `NSURLSession.h` + `NSProgress.h`, citado por file:line)

**Todos os APIs de N17c estão ABAIXO do floor `.v26` em toda plataforma → NENHUM `@available` gate em N17c** (mesmo que N17a/N17b — NÃO é o caso above-floor do N15b `submit`).

### Upload
- `URLSession.upload(for:fromFile:delegate:)` async — `.swiftinterface:16645` (`macOS 12 / iOS 15 / watchOS 8 / tvOS 15`) → `(Data, URLResponse)` — **buffered, NÃO AsyncBytes** (não há streaming upload via AsyncBytes). `delegate: (any URLSessionTaskDelegate)? = nil`.
- `URLSession.upload(for:from:delegate:)` async — `:16646` (in-memory `Data` body).

### Download
- `URLSession.download(for:delegate:)` async — `:16647` → `(URL, URLResponse)` — **temp-file URL, deleted quando a call retorna** (caller deve mover/ler antes). `delegate: (any URLSessionTaskDelegate)? = nil` (default).
- `URLSession.download(resumeFrom:delegate:)` async — `:16649` — resume via opaque `Data`.
- **`delegate:` é `(any URLSessionTaskDelegate)?`, NÃO `URLSessionDownloadDelegate?`** — a async overlay's delegate é o task-delegate surface. Para receber download callbacks, o delegate object adicionalmente conforms `URLSessionDownloadDelegate` (herda `URLSessionTaskDelegate`) e é passado como `any URLSessionTaskDelegate`. → **Um delegate object por download** (fresh per call, o shape N17a/N17b).

### URLSessionDownloadDelegate — `NSURLSession.h:1851-1884`
`@protocol NSURLSessionDownloadDelegate <NSURLSessionTaskDelegate>` `API_AVAILABLE(macos 10.9, ios 7, watchos 2, tvOS 9)`:
- `urlSession(_:downloadTask:didFinishDownloadingTo:)` `:1859` — **REQUIRED** (único; antes do `@optional` em `:1863`). Recebe o temp-file URL.
- `didWriteData` `:1865` — `@optional` (push progress).
- `didResumeAtOffset` `:1878` — `@optional`.
- `didCompleteWithError` — herdado de `URLSessionTaskDelegate` `:1689`, `@optional` lá.
- **NÃO `NS_SWIFT_SENDABLE`** (só `NSURLSessionDelegate` `:1642` é). → `final class : NSObject, URLSessionDownloadDelegate, Sendable` **deriva** Sendable (analogia N17b `NebulaWebSocketSessionDelegate` — conformância a `@objc` non-Sendable NÃO bloqueia derived Sendable numa `final class` com props `let` Sendable). **Probe EXIT=0** (`swiftc -typecheck -swift-version 6 -strict-concurrency=complete -warnings-as-errors`). **Sem `@unchecked`.**

### Resume data
- `URLSessionDownloadTask.cancel(byProducingResumeData:)` — `NSURLSession.h:942` — **completion-handler form only, NO async wrapper**. → wrap em `withCheckedContinuation` (precedent N17b `sendPing`).
- **Não há `var resumeData` no task.** Resume data: (a) completion do `cancel(byProducingResumeData:)`, ou (b) **`URLError.downloadTaskResumeData`** — `.swiftinterface:21645` (`macOS 10.15 / iOS 13 / watchOS 6 / tvOS 13`, abaixo do floor) — após download failed. UserInfo key: `NSURLSessionDownloadTaskResumeData`.
- `URLSession.download(resumeFrom:)` (`:16649`) é a async resume factory.

### Progress
- `URLSessionTask.progress` — `NSURLSession.h:731` (`macOS 10.13 / iOS 11 / watchOS 4 / tvOS 11`), `NSProgressReporting`, KVO. **`Progress` É `Sendable`** (`NSProgress.h:155` `NS_SWIFT_SENDABLE`).
- Delegate byte-count callbacks são o **único push-style progress** — download via `didWriteData` (`:1865`).
- **Não há async `for await` progress API** → N17c bridga `didWriteData` num consumer-facing `AsyncThrowingStream<Double, any Error>` (fração 0.0–1.0), o build-closure + `onTermination` pattern (precedent N17b `NebulaSSEEventStream`).

### Sendability verdicts (load-bearing)
| Type | Sendable? | Evidence |
|---|---|---|
| `URLSession` | **Yes** | `NSURLSession.h:201` `NS_SWIFT_SENDABLE` |
| `URLSessionDownloadTask` | **Yes** | `NSURLSession.h:928` |
| `Progress` | **Yes** | `NSProgress.h:155` |
| `URLComponents`/`URLQueryItem` | **Yes** | `.swiftinterface:13179`/`13335` |
| `URLSessionTaskDelegate`/`URLSessionDownloadDelegate` | **No** (not annotated) | deriva via N17b analogy, probe EXIT=0 |

### Multipart in Foundation — NONE
Grep de `.swiftinterface` por `multipart`/`form-data`/`boundary` → zero hits. `NebulaMultipartBuilder` é genuinamente novo.

### URLComponents / URLQueryItem (pagination cursor) — all below floor
`URLComponents.queryItems` (`:13291`), `URLQueryItem` (`:13335`), `percentEncodedQueryItems` (`:13297`). Sem gate Nebula.

## Decisões de design (load-bearing)

- **Delegate routing**: per-task `delegate:` (download callbacks) vs session delegate (pinning/auth — session-level). `NebulaDownloadDelegate` **não tem pinning**; `NebulaDownload.pinned(by:)` seta o `NebulaURLSessionDelegate` como session delegate. **Zero N17a change, sem `import Security` no product target.**
- **Custom loops, NÃO `NebulaRetry.withPolicy`**: paged cursor mutates per page; download resume data mutates the attempt (`download(resumeFrom:)`). `withPolicy` é nullary — não pode carry mutating state. Precedent SSE `NebulaSSEEventStream.swift:17-24`.
- **Resume data challenge**: `URLSession.download(for:)` async overlay não expõe o task → `cancelByProducingResumeData()` captura o task no delegate via `downloadTaskBox: Mutex<URLSessionDownloadTask?>` (um `weak var` quebraria derived Sendable). Failure-path resume lê `URLError.downloadTaskResumeData` do caught error no loop.
- **Completion race** (delegate resolve antes de `value()` registrar) → `NebulaDownloadCompletion` state machine (pending/awaiting/resolved).
- **Cancellation semantics** (N17b): consumer's `for try await` ends normally on cancel (`Iterator.next()` returns `nil`, NÃO throw `CancellationError`); `value()` throws `CancellationError`; `onTermination → loop.cancel()`. Importante: `withCheckedThrowingContinuation` NÃO auto-throws on Task cancel sem `withTaskCancellationHandler` — consumer cancellation surfaces via o **loop** (`Task.checkCancellation()`/`URLError(.cancelled)` branch resume o completion box), NÃO via o box.
- **Gateway-compatibility**: multipart produz `Data`+content-type fed em `NebulaHTTPBody.data(_:contentType:)` — nenhum case novo, sem ripple. `NebulaHTTPGateway` bufferizado unchanged.
- **Boundary**: 16 bytes random (`UInt8.random(in: 0...255)`) → `nebulaHexEncodedString()` → `"----NebulaBoundary<HEX>"`. Sem `import CryptoKit`.
- **`NebulaResultPipeline<T: Sendable>: Sendable`** precedent para `NebulaPagedSequence<Page: Sendable>: Sendable`.
- **Open-struct error template**: copy `NebulaSSEError` verbatim — `NebulaFailure, Equatable, Hashable` + nested `Kind` + `coarseKind` (com `default → .unknown`) + `toNebulaError(kind:)` + factory statics. **Nenhum caso novo em `NebulaError.Kind`**. `underlying = NebulaError.Box(NebulaError(error: error))`.

## Testability stance (documented limitation)

- **Multipart**: pura — unit-tested diretamente (8 tests de builder + 2 de temp-file writer + 4 de error mapping).
- **Pagination**: pura via canned `@Sendable` closures (loop + stop + error + cancellation graceful + Sendable) — 7 tests.
- **Download**: delegate lifecycle synthesized (move-to-destination, progress fractions, task capture) + race-safe completion box (resolve-before-register, failure, idempotent) + error/resume-data extraction seams (`URLError.downloadTaskResumeData` via userInfo key `NSURLSessionDownloadTaskResumeData`) — 18 tests.
- **Live round-trip via `URLProtocol`: HANGS** — `URLProtocol` não bridga clean o async `URLSession.download(for:delegate:)` temp-file path (a overlay nunca completa; `didFinishDownloadingTo` não dispara). Mirror do pragmatic stance do N17a: seam de transporte não-injetável é documentado, não forçado. Live round-trip é compile-only guarantee (a façade builda nas 5 plataformas; move+progress+resume verificado nos seams delegate/loop). Consumer cancellation via o loop (NÃO via `withCheckedThrowingContinuation` auto-cancellation).

## Invariants

- `import Foundation` + `import Synchronization` only (product target). **Sem `import Security`** (pinning forwarded ao delegate N17a). **Sem `import CryptoKit`** (multipart não hash). **Sem `import Network`** (downloads usam `URLSession`, não `NWListener`).
- **Nenhum `@available` gate** nos novos arquivos (all below-floor).
- **Zero `@unchecked Sendable` em value types** (`NebulaDownloadDelegate` é `final class` — derived, não `@unchecked`).
- **Nenhum case novo em `NebulaError.Kind`** (envelope fechado; `coarseKind` mapeia para `.network`/`.unknown`).
- `NebulaDownloadConfiguration`/`NebulaDownloadHandle` **Sendable, NÃO `Equatable`** (closures `@Sendable`).
- `Package.swift` diff vazio (`dependencies: []` pristine, sem `resources:`).
- `NebulaHTTPBody`/`NebulaHTTPRequest`/`NebulaHTTPResponse`/`NebulaHTTPGateway`/`NebulaHTTPClient`/`NebulaURLSessionDelegate`/`NebulaHTTPSession` diffs vazios.

## Deferred (N17 split completo)

- N18 (StoreKit IAP), A1–A3 (Aurora migration), N11b (runnable composition example), N15c (`BGContinuedProcessingTask`) per o hub [[nebula-app-readiness-research]].
- Tag `0.6.0`…`0.16.0` — pending owner gate (work in place, não committed).
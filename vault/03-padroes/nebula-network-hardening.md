---
tags: [nebula, architecture, network, ssl-pinning, websocket, sse, multipart, swift]
aliases: [nebula network hardening, NebulaHTTPInterceptor, NebulaSSLPinning, NebulaWebSocket, NebulaSSEEventStream, NebulaMultipartBuilder, NebulaDownload, NebulaPagedSequence, nebula streaming]
related: [[nebula-app-readiness-research]], [[nebula-network-endpoint-client]], [[nebula-keychain-auth]]
status: researched
researched: "2026-07-19"
---

# Nebula — Network hardening + advanced transport

> Research depth for the network-hardening dimension of [[nebula-app-readiness-research]]. Verified against `Foundation.swiftmodule/arm64e-apple-ios.swiftinterface` + `NSURLSession.h` + `Security.framework/Headers/SecTrust.h`/`SecCertificate.h` (Xcode 27 Beta 3). UNVERIFIED items flagged inline.

## Dimension overview

Apple's network stack splita clean em duas seams: (a) **trust/cert policy** vive em `URLSessionDelegate` (`urlSession(_:didReceive:completionHandler:)` + `Sec*` C APIs em `Security.framework`) e Apple agora prefere **declarative `NSPinnedDomains` no `Info.plist`** (iOS 14+) sobre pinning programático; (b) **advanced transport** (streaming, WebSocket, download-to-disk, multipart) é `URLSession` async API surface (`bytes(for:)`, `download(for:)`, `URLSessionWebSocketTask`) — todos Foundation-tier, todos abaixo do floor `.v26`, todos Sendable no boundary value-type. Interceptor/middleware **não é concern Apple** — Alamofire's `RequestInterceptor` (`Adapter`+`Retrier`, ambos `: Sendable` com `@Sendable` completion handlers) é o pattern third-party canônico para espelhar sem depender.

## Apple-native APIs + best-practice pattern

### (a) SSL/TLS pinning
- **Declarative (Apple-preferred)**: `NSPinnedDomains`/`NSPinnedCAIdentities`/`NSPinnedLeafIdentities` no `Info.plist` ATS, iOS 14+ — pin **CA SPKI-SHA256-Base64** (rotaciona menos que leaf), sempre inclua **backup pins**. Apple article "Identity Pinning" (2021). Último WWDC relevante: WWDC19 709 "Cryptography and Your Apps".
- **Programmatic** (quando framework-level control é necessário): implement `URLSessionDelegate.urlSession(_:didReceive:completionHandler:)` → chame `SecTrustEvaluateWithError` primeiro (NÃO skip default eval), depois pull leaf/CA cert com `SecTrustGetCertificateAtIndex`, derive SPKI via `SecCertificateCopyKey` → `SecKeyCopyExternalRepresentation` → SHA-256 → compare contra pinned Base64 hashes. **Verified** em `Security.framework/Headers`:
  - `SecTrustEvaluateWithError` — `SecTrust.h:427` `API_AVAILABLE(macos(10.14), ios(12.0), tvos(12.0), watchos(5.0))` ✅ abaixo floor
  - `SecTrustGetCertificateAtIndex` — `SecTrust.h:536` (sem `API_AVAILABLE` ⇒ iOS 7.0 era) ✅
  - `SecTrustCopyPublicKey` — `SecTrust.h:489` ✅
  - `SecCertificateCopyKey` — `SecCertificate.h:157` `API_AVAILABLE(macos(10.14), ios(12.0), watchos(5.0), tvos(12.0))` ✅ — preferido sobre `SecCertificateCopyPublicKey` (cross-platform)
  - `SHA256` — `CryptoKit.swiftinterface:307` `public struct SHA256 : Swift::Sendable` (sem `@available` ⇒ iOS 13 floor) ✅ já usado por `NebulaHashAlgorithm`
- **Binding tension**: `NebulaHTTPGateway` hoje toma `session: URLSession = .shared` e nunca delegate. Para anexar pinning delegate, o gateway deve own o `URLSession` que cria — i.e. aceitar `URLSessionConfiguration` + delegate, ou aceitar `URLSession` pre-built. `init(configuration:delegate:delegateQueue:)` é ObjC class method — `NSURLSession.h:255` `+sessionWithConfiguration:delegate:delegateQueue:` (iOS 7.0) ✅.

### (b) Interceptor / middleware chain
- **Sem Apple API.** Alamofire é a referência: `RequestInterceptor.swift`. Dois protocols `: Sendable`:
  - `RequestAdapter` — `adapt(_:for:completion:)` transforma `URLRequest` pre-send (auth-token injection), `@Sendable` completion.
  - `Retrier` — `retry(_:for:dueTo:completion:)` retorna `RetryResult` (`retry`/`retryWithDelay`/`doNotRetry`/`doNotRetryWithError`), powers 401-refresh-and-retry.
  - `Interceptor` compõe arrays ordenados de adapters + retriers; adapters rodam sequencialmente short-circuitando em failure, retriers rodam até um dizer retry. Alamofire 5.11 (Dec 2025) adicionou per-Request chaining (PR #3996).
- **Pattern translation to Nebula**: `NebulaHTTPInterceptor` protocol com `@Sendable` async `adapt(_ request: URLRequest) async throws -> URLRequest` e `retry(_ request: URLRequest, response: NebulaHTTPResponse, error: NebulaError) async -> NebulaRetryDecision`. Compõe num ordered `struct NebulaHTTPInterceptorChain: Sendable` que wrap `send(_:)`. Espelha o idiom decorator `.logged`/`.measured` já em Nebula.
- **Swift 6 Sendable concern**: a chain hold `[any NebulaHTTPInterceptor]` — `any` de um protocol `Sendable` é Sendable; a chain struct deriva `Sendable` se todo elemento é. O 401-refresh interceptor hold `Mutex<TokenBucket>` para o in-flight refresh singleton (match CLAUDE.md `Mutex<T>` rule). Sem `@unchecked` se o token store é `Mutex`.

### (c) Streaming — SSE + WebSocket
- **SSE** = HTTP `text/event-stream` consumido via `URLSession.bytes(for:)` → `.lines` → parse `data:`/`event:`/`id:` prefixes per spec SSE. **Verified**:
  - `URLSession.bytes(for:delegate:)` — `Foundation.swiftinterface:16670` `@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)` ✅ (abaixo floor, sem gate)
  - `URLSession.AsyncBytes` — `:16659` `public struct AsyncBytes : AsyncSequence, Swift::Sendable` ✅ Sendable, `Element = UInt8`
  - `AsyncSequence.lines` — `:14825` `@available(macOS 12.0, iOS 15.0, ...)` retorna `AsyncLineSequence<Self>` (`:14802`), `Element = String`, Sendable quando `Base: Sendable` (`:14822`) ✅
- **WebSocket** = native `URLSessionWebSocketTask`. **Verified**:
  - `URLSessionWebSocketTask` extension — `Foundation.swiftinterface:16564` `@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)` ✅ (abaixo floor, sem gate)
  - `URLSessionWebSocketTask.Message` enum — `:16566` `public enum Message : Swift::Sendable` (`.data`/`.string`) ✅
  - `send(_:)` async — `:16572`; `receive() async` — `:16585` ✅
  - Factory: `webSocketTask(with:)` — `NSURLSession.h:499/511/523` `API_AVAILABLE(macos(10.15), ios(13.0), watchos(6.0), tvos(13.0))` ✅
  - Delegate `URLSessionWebSocketDelegate` — `NSURLSession.h:1923` (`didOpenWithProtocol`/`didCloseWithCode:reason:`) ✅
- **Sendability**: `URLSessionWebSocketTask` é class — **não** Sendable por default (não anotado `NS_SWIFT_SENDABLE` em `NSURLSession.h:1123`). Façade/region isolation required: `final class NebulaWebSocket` (ou actor) wrap o task é o idiom Nebula (match "final class façade sobre non-Sendable Apple types").

### (d) Multipart/form-data
- **Sem Apple API.** Hand-roll: set `Content-Type: multipart/form-data; boundary=...`, build body como `Data` com `--<boundary>\r\nContent-Disposition: form-data; name="..."; filename="..."\r\nContent-Type: ...\r\n\r\n<bytes>\r\n` per part, termine com `--<boundary>--\r\n`. Use `URLRequest.httpBody = Data`. Pure-Foundation, sem availability gate, fully Sendable (`Data` é Sendable).
- **Caveat**: streaming uploads (`URLSession.upload(for:fromFile:)`) evitam hold o body inteiro em memória — `Foundation.swiftinterface:16645` `upload(for:fromFile:delegate:)` iOS 15+ ✅. Um `NebulaMultipartBuilder` que emite `Data` é fine para payloads típicos; uma variante streaming escreve parts para temp file então usa `upload(for:fromFile:)`.

### (e) Download to disk
- **Async API**: `URLSession.download(for:delegate:)` retorna `(URL, URLResponse)` — o URL é um **temporary** file que o caller deve mover antes da call retornar. **Verified** `Foundation.swiftinterface:16647` `@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)` ✅ (abaixo floor).
- **Resume from cancellation**: `URLSession.download(resumeFrom:)` — `:16649` mesma availability ✅. Em cancellation/failure, `URLError` userInfo key `NSURLSessionDownloadTaskResumeData` (`NSURLSession.h:1937` `API_AVAILABLE(macos(10.9), ios(7.0), ...)`) hold `Data` para resumption.
- **Delegate path** (background/progress): `URLSessionDownloadDelegate.urlSession(_:downloadTask:didFinishDownloadingTo:)` — `NSURLSession.h:1857` (required) + `didWriteData`/`didResumeAtOffset` (optional) ✅.
- **Façade**: Nebula wrap `download(for:)` + uma move-to-destination closure + resume-data capture num `NebulaDownload` value type; a URLSession instance é re-usada do gateway.

### (f) Pagination `AsyncSequence`
- **Sem Apple API.** Pattern: `NebulaPagedSequence<Response>` wrap um async `next()` que chama `send(_:)` com o cursor do response anterior, surfacing `AsyncThrowingStream` de decoded items. `AsyncThrowingStream` é o concrete return type mandated pelo Nebula (CLAUDE.md binding). Cursor variants: offset/limit, page-number, Link-header (RFC 5988 `rel="next"`), cursor opaque token. `URLResponse.value(forHTTPHeaderField:)` (`Foundation`) extrai o Link header ✅.

## Sendability & availability

| API | Sendable? | Floor | Gate? |
|---|---|---|---|
| `URLSession` (class) | ✅ `NS_SWIFT_SENDABLE` (`NSURLSession.h:201`) | iOS 7 | Não |
| `URLSessionConfiguration` | ✅ Sendable | iOS 7 | Não |
| `URLSessionDelegate`/`TaskDelegate` (protocols) | ✅ `NS_SWIFT_SENDABLE` (`NSURLSession.h:1644`) | iOS 7 | Não |
| `init(configuration:delegate:delegateQueue:)` | N/A (ctor) | iOS 7 (`NSURLSession.h:255`) | Não |
| `URLSession.bytes(for:)`/`AsyncBytes` | ✅ struct `: AsyncSequence, Sendable` | iOS 15 (`:16659`) | Não |
| `AsyncBytes.lines`/`AsyncLineSequence` | ✅ Sendable quando Base Sendable (`:14822`) | iOS 15 (`:14825`) | Não |
| `URLSession.download(for:)`/`(resumingFrom:)` | retorna `(URL, URLResponse)` — ambos Sendable | iOS 15 (`:16647`) | Não |
| `URLSessionWebSocketTask` (class) | ❌ NÃO Sendable (`NSURLSession.h:1123` unannotated) | iOS 13 (`:16564`) | Não — façade/actor required |
| `URLSessionWebSocketTask.Message` | ✅ `enum : Sendable` (`:16566`) | iOS 13 | Não |
| `SecTrustEvaluateWithError`/`SecCertificateCopyKey`/`SecTrustGetCertificateAtIndex` | C, trivially Sendable | iOS 12/12/7 | Não |
| `CryptoKit.SHA256` | ✅ `struct : Sendable` (`CryptoKit.swiftinterface:307`) | iOS 13 | Não |
| `URLSession.upload(for:fromFile:)` | ✅ | iOS 15 (`:16645`) | Não |

**UNVERIFIED**: `URLSessionWebSocketTask` conformance `Sendable` no runtime Swift module — só chequei o ObjC header (sem `NS_SWIFT_SENDABLE`); a extension `.swiftinterface:16564` adiciona async `send`/`receive` mas **NÃO** adiciona conformance `Sendable` à class. Trate a class como non-Sendable. Também unverified: se `NWPathMonitor`-driven "wait for connectivity" retry (Alamofire `OfflineRetrier`) pertence ao Nebula — `Network.framework` é allowed mas `NWPathMonitor` class Sendability não checada.

## Nebula-scope verdict

| Surface | Veredito | Rationale | Tensão |
|---|---|---|---|
| `NebulaSSLPinning` (SPKI-hash delegate façade) | **Façade (pendente Q)** | Pinning programático é real mas Apple prefere `Info.plist` `NSPinnedDomains`; façade Nebula faz sentido só para framework-level/per-endpoint pinning que ATS não expressa. `final class` delegate wrap `Mutex<[Set<SPKIHash>]>` | Gateway deve aceitar delegate — `init(configuration:delegate:)` change backward-compatible se delegate default nil. **`import Security` NÃO está na lista allowed do CLAUDE.md** — confirmar se permitido. Se não, pinning = **App-only** (consumer wires o delegate) |
| `NebulaHTTPInterceptor` + `NebulaHTTPInterceptorChain` | **Port + Config** | Pure-Swift middleware protocol, sem Apple API. Espelha Alamofire `RequestAdapter`/`Retrier` com `@Sendable` async methods. Compõe em `send(_:)` como default-extension decorator (backward-compatible). Auth-token + 401-refresh + logging são os interceptors canônicos | Nenhuma — all-Swift, deriva Sendable. O 401-refresh interceptor's in-flight refresh singleton precisa `Mutex<TokenBucket>` (match CLAUDE.md). Sem novo `NebulaError.Kind` (per-layer `NebulaFailure`) |
| `NebulaWebSocket` (port + façade) | **Port + Façade** | `URLSessionWebSocketTask` non-Sendable → `final class` (ou `actor`) façade. `NebulaWebSocketClient` protocol port + `NebulaURLSessionWebSocket` concrete façade match o idiom "port + config + façade" | WebSocket class non-Sendable → façade required (rule-compliant). `URLSessionWebSocketDelegate` é `@objc` `@optional` — `final class` conformando via `@objc` methods é o path; `@objc` + Sendable precisa care (region isolation ou `Mutex`) |
| SSE bytes stream (`NebulaSSEEventStream`) | **Façade** | `URLSession.bytes(for:).lines` já é perfeito; Nebula adiciona o SSE-frame parser (`data:`/`event:`/`id:`/retry) e surfaces `AsyncThrowingStream<NebulaSSEEvent, Error>`. Thin value-type façade sobre `AsyncBytes` | Nenhuma — `AsyncBytes` + `AsyncLineSequence` Sendable; parser pure-Swift. CLAUDE.md manda concrete `AsyncThrowingStream` return ✅ |
| `NebulaMultipartBuilder` | **Façade** | Sem Apple API; pure-`Data` body builder. Retorna `NebulaHTTPBody` para `NebulaHTTPRequest` consumir unchanged. Variante streaming usa `upload(for:fromFile:)` para temp file | Nenhuma — pure Foundation `Data` |
| Download-to-disk (`NebulaDownload`) | **Façade** | `URLSession.download(for:)` retorna temp `URL`; Nebula wrap move-to-destination + resume-data capture + progress (via delegate ou `AsyncStream<Double>`) | Move-to-destination closure deve ser `@Sendable` (file I/O off the caller's actor). Resume data é `Data` (Sendable) |
| Pagination `AsyncSequence` | **Façade** | Generic `NebulaPagedSequence<Page>` sobre `send(_:)` com pluggable cursor extractor. Surfaces `AsyncThrowingStream<Element, Error>` | Nenhuma — pure-Swift sobre o port existente |
| **Defer** (per roadmap atual) | — | request middleware/interceptors, streaming, multipart, download, pagination estão listados DEFERRED — esta pesquisa confirma que todos são feasible sem novas deps | — |

## Recommended waves

- **N17a — Network interceptors + pinning scaffolding.** `NebulaHTTPInterceptor` protocol (`adapt`/`retry`), `NebulaHTTPInterceptorChain` ordered composer, `NebulaHTTPGateway.send` wired através da chain, built-in `NebulaAuthTokenInterceptor` (Mutex-guarded refresh) + `NebulaLoggingInterceptor`. Pinning: add `delegate:` param ao gateway init (backward-compatible default nil); ship `NebulaSSLPinning` SPKI-hash delegate façade **só se** `import Security` for ruled in-bounds — senão documentar como App-only e prover o delegate injection point. Deps: N5 (gateway — shipped), N10 (auth interceptor — ou shipar aqui como parte).
- **N17b — Streaming transport.** `NebulaSSEEventStream` (parser sobre `bytes(for:).lines`), `NebulaWebSocketClient` port + `NebulaURLSessionWebSocket` `final class` façade (Send `Message`, `receive() async`, close-code bridging para `NebulaError`). Deps: N17a (interceptor chain powers WS reconnect + SSE retry).
- **N17c — Bodies & downloads.** `NebulaMultipartBuilder` (Data + streaming-via-temp-file variants), `NebulaDownload` façade (move-to-destination, resume-data, progress `AsyncStream<Double>`), `NebulaPagedSequence<Page>` generic pagination. Deps: N5 (gateway) + N17a (interceptors para retry).

## Open question for the binding-rule owner
`import Security` (para `SecTrust*`/`SecCertificate*`) **NÃO está na lista allowed explícita do CLAUDE.md** ("Foundation + Network + Synchronization"). Pinning delegate-based requer. Se `Security` for ruled out, `NebulaSSLPinning` façade vira **App-only** e N17a ship só o delegate injection point + interceptor chain. Confirmar antes do design N17a. (Mesma Q do hub — ver [[nebula-app-readiness-research]].)

## Sources
- Apple "Identity Pinning" (2021) — https://developer.apple.com/news/?id=g9ejcf8y
- WWDC19 709 "Cryptography and Your Apps" — https://developer.apple.com/videos/play/wwdc2019/709/
- Alamofire RequestInterceptor.swift — https://github.com/Alamofire/Alamofire/blob/master/Source/Features/RequestInterceptor.swift
- Alamofire AdvancedUsage.md — https://github.com/Alamofire/Alamofire/blob/master/Documentation/AdvancedUsage.md
- Alamofire PR #3996 (per-Request chaining 5.11) — https://github.com/Alamofire/Alamofire/pull/3996
- Secure Vale — "Deep Dive into Certificate Pinning on iOS" — https://securevale.blog/articles/deep-dive-into-certificate-pinning-on-ios/
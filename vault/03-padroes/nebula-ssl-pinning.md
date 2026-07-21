---
tags: [nebula, architecture, network, ssl-pinning, security, transport, swift, concurrency, sendable, urlsession]
aliases: [nebula ssl pinning, NebulaSSLPinning, NebulaSSLPinningPin, NebulaSSLPinningEvaluator, NebulaSSLPinningResult, NebulaURLSessionDelegate, NebulaHTTPSession, NebulaPinnedSession, NebulaSSLPinningError, nebula spki pinning]
related: [[nebula-network-hardening]], [[nebula-app-readiness-research]], [[nebula-clean-architecture-toolkit]], [[nebula-error-taxonomy-toolkit]], [[nebula-async-flow]]
status: shipped
shipped: "0.14.0 (Wave N17a, 2026-07-20)"
---

# Nebula — SSL/TLS public-key pinning (shipped)

> Shipped note for the network-hardening dimension of [[nebula-app-readiness-research]] (wave N17a, a primeira sub-wave do N17 split). Source of truth: `Sources/Nebula/Architecture/Network/Pinning/` (5 arquivos) + `Tests/NebulaTests/ArchitectureSSLPinningTests.swift` + `Sources/Nebula/Nebula.docc/ArchitectureSSLPinning.md`. Parent research: [[nebula-network-hardening]].

## O que shipou (Nebula 0.14.0)

- **`NebulaSSLPinningPin`** — `Sendable`/`Equatable`/`Hashable` struct: o 32-byte SHA-256 digest da DER external representation da public key de um cert. `init?(digest: Data)` (valida `count == 32`) e `init?(hexDigest: String)` (delega para `Data(nebulaHexEncoded:)` — single source of truth do codec hex — e re-valida 32 bytes, então um hex não-32-byte falha em vez de produzir um pin malformado). Round-trip via `hexDigest`. Sendable derived (`Data`).
- **`NebulaSSLPinning.HostPins`** — `Sendable`/`Equatable`/`Hashable`: `host: String` + `pins: Set<NebulaSSLPinningPin>`.
- **`NebulaSSLPinning`** — a **`Sendable` policy value type** (pure data, sem `URLSession`, sem `SecTrust`). Fields: `hostPins: [HostPins]`, `includeSubdomains: Bool = false`, `validateChainFirst: Bool = true` (pinning é **additive ao system trust** — nunca substitui o OS trust store), `failClosedForUnknownHosts: Bool = true` (host sem pin → cancel; `false` → default handling). Fluent `.withHostPins/.withIncludeSubdomains/.withValidateChainFirst/.withFailClosedForUnknownHosts` retornando o tipo concreto (mirror `NebulaGatewayConfiguration`). `static pins(for:_:)` single-host convenience. Sendable derived (todos os fields Sendable).
- **`NebulaSSLPinningResult`** — `Sendable`/`Equatable` enum: `.matched(pin:certificateIndex:)` / `.noMatchingPin` / `.noPinForHost` / `.chainValidationFailed(message:)` / `.spkiExtractionFailed(message:)`.
- **`NebulaSSLPinningEvaluator`** — `enum` namespace com `static func evaluate(trust: SecTrust, host: String, policy: NebulaSSLPinning) -> NebulaSSLPinningResult`. **Pure function**, sem dependência de `URLSession` — chamável do delegate ou de testes com `SecTrust` sintético. Algorithm OWASP "any position" (match em **qualquer** cert da chain — leaf ou intermediate/CA — sobrevive a leaf rotation), additive ao system trust:
  1. Se `validateChainFirst` → `SecTrustEvaluateWithError`; chain rejeitada pelo OS → `.chainValidationFailed`.
  2. Resolve pins para `host` (exact match, depois parent-domain walk quando `includeSubdomains`); nenhum → `.noPinForHost`.
  3. `SecTrustCopyCertificateChain(trust) as? [SecCertificate]`.
  4. Por cert: `SecCertificateCopyKey` → `SecKeyCopyExternalRepresentation` → `(der as Data).nebulaDigest(of: .sha256)` → se digest ∈ pin set → `.matched`. (Key não-extraível num cert não é fatal — `continue`.)
  5. Nenhum match mas pelo menos um SPKI extraído → `.noMatchingPin`; se **todo** cert falhou key/DER extraction (ou a chain não pôde ser copiada) → `.spkiExtractionFailed(message:)` — diagnóstico truthful para um caller que faz bridge para `NebulaSSLPinningError` (refinamento do code-review: antes o all-fail caía em `.noMatchingPin`, que é enganoso).
  - O host-lookup (exact + subdomain walk) é fatorado como `internal resolvedPins(for:policy:)` — testável independentemente de `SecTrust`. O walk para **antes** do single-label public suffix (`labels.count >= 3` guard; `com` não casa `api.example.com`). **Matching é case-insensitive** (RFC 1035 — `host` e o stored `HostPins.host` são ambos `.lowercased()` antes da comparação; stored data não é mutado) — refinamento do code-review: antes o matching era case-sensitive, o que faria um `HostPins(host: "Example.Com")` falhar contra um `URLProtectionSpace.host` lowercase.
- **`NebulaURLSessionDelegate`** — `final class : NSObject, URLSessionDelegate, Sendable`. `let pinning: NebulaSSLPinning` + `let logger: NebulaLogger?`. `Sendable` **derived** — só `let` props Sendable, **sem `@unchecked`** (veredito abaixo). O `@objc optional urlSession(_:didReceive:completionHandler:)` é um thin guard → evaluate → map → completion: non-server-trust challenge → `.performDefaultHandling`; server-trust → `evaluate` → loga falha via `logger?.log(.error, …)` → `disposition(for:policy:trust:)` → completion. O delegate **não throws** (o método `@objc optional` não tem `throws`); falha → `.cancelAuthenticationChallenge` → `URLSession` surfaces `URLError` → `NebulaHTTPGateway` já faz `catch let urlError as URLError { NebulaError(urlError: urlError) }`. **Nenhuma mudança no gateway.** O `internal disposition(for:policy:trust:)` é a seam testável: `.matched → (.useCredential, URLCredential(trust:))`; `.noPinForHost → failClosed ? .cancel : .performDefaultHandling`; `.noMatchingPin/.chainValidationFailed/.spkiExtractionFailed → .cancelAuthenticationChallenge`.
- **`NebulaHTTPSession` / `NebulaPinnedSession`** — `enum` namespace + `struct` pair para o session builder: `NebulaHTTPSession.pinned(by:configuration:logger:) -> NebulaPinnedSession` builda `NebulaURLSessionDelegate` + `URLSession(configuration:delegate:delegateQueue:)` e retorna **ambos** (`URLSession` NÃO retém strong o delegate — footgun documentado; reter o `NebulaPinnedSession` value é suficiente para o lifetime do delegate). Default `configuration: .ephemeral` (pinning session tipicamente não compartilha cookie/cache global). Um `enum` namespace (não instances) evita extender `URLSession` (colidiria estilisticamente com `URLSession.shared`/`URLSession(configuration:)`). **Sem accessor process-wide** — pinning é per-session, não process-wide como logging/measurement.
- **`NebulaSSLPinningError`** — open-struct (`NebulaFailure, Equatable, Hashable`) + nested `Kind` (presets `.noMatchingPin`/`.noPinForHost`/`.chainValidationFailed`/`.spkiExtractionFailed`/`.cancelled`/`.unknown`, kebab-case) + `coarseKind` (`.network` para os 4 pinning kinds; `.unknown` para cancelled/unknown) + `toNebulaError(kind:)` (domain `"Nebula.NebulaSSLPinningError"`, `meta["NebulaCode"] = code`). Factory statics com `underlying: NebulaError.Box?`. **Sem novos `NebulaError.Kind` cases**. Mirror exato do `NebulaHTTPServerError`. Precedente [[nebula-error-taxonomy-toolkit]].

## Correção de escopo: pinning é transport-layer, NÃO interceptor (N17a vs N10)

**O ponto-chave do planejamento N17a, e uma correção empírica do research.** O research ([[nebula-network-hardening]]) listava N17a como "interceptors + pinning scaffolding". **Empiricamente, a metade "interceptors" já shipou em N10/0.7.0** — `NebulaHTTPInterceptor`/`NebulaHTTPInterceptorChain`/`NebulaAuthInterceptor` já existem em `Sources/Nebula/Architecture/Network/`. Então N17a é **só** a metade de pinning.

E pinning é uma concern de **transport-layer, não de interceptor**: uma falha de pinning surfaces como `URLError` do `URLSession` *antes/debaixo* do `data(for:)` — a avaliação de trust tem que acontecer no layer `URLSessionDelegate`, não num interceptor `adapt`/`retry` (um interceptor só muta o `URLRequest` / reage a um erro thrown, não avalia trust). Logo N17a:

- **NÃO toca `NebulaHTTPGateway`** (o gateway já aceita um `session: URLSession` opaco — Option A: um caller injeta um session delegate-configurado hoje, com zero mudanças no gateway).
- **NÃO adiciona `NebulaGatewayConfiguration.pinning`** (pinning é per-session, não per-config).
- **NÃO adiciona accessor process-wide** (`NebulaSSLPinningConfig`) — pinning não é process-wide como logging/measurement.
- A lista de configs em `Nebula.md` é **inalterada**.

## Ground truth do Security framework (sem `.swiftinterface`)

**O `Security` framework é C/Obj-C via `module.modulemap` — NÃO há `.swiftinterface`** (verificado: só `Security.framework/Modules/module.modulemap` existe, sem `.swiftmodule`). O ground truth são os headers `.h`, citados por file:line. **WebFetch hallucina availability** (precedente [[apple-docs-mcp-not-working]]) — os headers são autoritativos. Todos os símbolos de pinning são **abaixo do floor `.v26` em todas as 5 plataformas → NENHUM gate `@available` em N17a**:

| Símbolo | Header:line | Availability | Papel |
|---|---|---|---|
| `SecTrustEvaluateWithError(_:_:) -> Bool` | `SecTrust.h:425` | mac 10.14 / iOS 12 / tvOS 12 / watchOS 5 | chain validation (default on) |
| `SecTrustCopyCertificateChain(_:) -> CFArray?` | `SecTrust.h:655` | mac 12 / iOS 15 / tvOS 15 / watchOS 8 | chain accessor preferido (substitui o deprecated `SecTrustGetCertificateAtIndex`) |
| `SecCertificateCopyKey(_:) -> SecKey?` | `SecCertificate.h:155` | mac 10.14 / iOS 12 / tvOS 12 / watchOS 5 | cross-platform key extractor (NÃO o deprecated platform-split `SecCertificateCopyPublicKey`) |
| `SecKeyCopyExternalRepresentation(_:_:) -> CFData?` | `SecKey.h:854` | mac 10.12 / iOS 10 / tvOS 10 / watchOS 3 | DER external rep (PKCS#1 RSA / ANSI X9.63 ECDSA) |
| `SecCertificateCreateWithData` / `SecTrustCreateWithCertificates` / `SecPolicyCreateSSL` | `SecCertificate.h`/`SecTrust.h`/`SecPolicy.h` | abaixo do floor | test-only: buildar `SecTrust` sintético |

**Foundation (`NSURLSession.h`):** `URLSessionDelegate` protocol é `NS_SWIFT_SENDABLE` (`:1642`); `urlSession(_:didReceive:completionHandler:)` é `@objc optional`, completion `@escaping @Sendable`, **sem variante async** (sem `NS_SWIFT_ASYNC`); `URLSession.AuthChallengeDisposition` = `.useCredential`/`.performDefaultHandling`/`.cancelAuthenticationChallenge`/`.rejectProtectionSpace`; `URLProtectionSpace.serverTrust: SecTrust?` (readonly). `URLSession` é `NS_SWIFT_SENDABLE` (`:201`).

`import Security` é **in-bounds** — o precedente Keychain (`import Security` em `Architecture/Keychain/`) estabelece isso; a Q em aberto do research/hub ("`import Security` NÃO está na lista allowed explícita do CLAUDE.md") está **resolvida** — Security é um framework Apple non-UI e o CLAUDE.md admite "any non-UI Apple system framework". Aparece só no evaluator + no delegate (a policy/error/session-builder são Foundation-only).

## A Sendability — `final class : NSObject, URLSessionDelegate, Sendable` DERIVED (sem `@unchecked`)

**Resolvido por probe (EXIT=0, zero warnings sob Swift 6 strict concurrency, Xcode 27 Beta 3 SDK):** `final class : NSObject, URLSessionDelegate, Sendable` com `let pin: <Sendable>` **deriva** `Sendable` — **sem `@unchecked`**. `URLSessionDelegate` é anotado `NS_SWIFT_SENDABLE`, então conformar a um protocol `@objc` Sendable **não bloqueia** derived `Sendable` num `final class` cujos únicos stored props são `let` imutáveis de tipo Sendable. Isto casa **exatamente** com o precedente `NebulaUNNotificationCenter` (`final class : NSObject, NebulaNotificationCenter, UNUserNotificationCenterDelegate, Sendable`, derived, sem `@unchecked` — ver [[nebula-notifications]]). `NSObject` é Foundation (não UIKit); é necessário porque `URLSessionDelegate` é um protocol `@objc` com métodos `@objc optional`, então a classe conformante precisa ser Obj-C-runtime-dispatched.

Isto é a **diferença crucial vs N15b** ([[nebula-background-tasks]]): lá, o `BGTask` non-Sendable chega numa closure `@Sendable` e não pode ser stored num `Mutex` (region-isolation wall) → exigiu um `final class @unchecked Sendable NebulaBGTaskBox` reference-type wrapper. Aqui **nenhum** tipo non-Sendable precisa ser stored — a policy é value Sendable, o `SecTrust` é consumido e descartado dentro da chamada síncrona do delegate (não persisted). Então **zero `@unchecked`** em todo N17a (policy/value types derived, delegate derived, `NebulaPinnedSession` derived).

## Restrição de testabilidade (e a seam `disposition(for:policy:trust:)`)

- O **evaluator puro** é fully unit-testable no macOS host com um **`SecTrust` sintético**: um cert RSA-2048 self-signed (CN=test.example.com) é embedded como literal `[UInt8]` (694 bytes, gerado offline via `openssl req -x509 … -outform DER`, baked no source — sem `resources:` SPM, sem bundle). `SecCertificateCreateWithData` → `SecTrustCreateWithCertificates(cert, SecPolicyCreateSSL(true, host), &trust)` → assert `.matched`/`.noMatchingPin`/`.noPinForHost`/`.chainValidationFailed` (cert self-signed falha o OS trust no macOS — exatamente o path `validateChainFirst: true` assertado). O **golden pin** (`7badc2c8…3b2a`, SHA-256 da public-key DER) é computado uma vez via o mesmo path de API do evaluator e hardcoded.
- O **método delegate NÃO é round-trip testável**: `URLProtectionSpace.serverTrust` é `nil` a não ser que o sistema tenha criado o space durante um handshake real, e o `URLProtectionSpace.init(host:port:protocol:realm:authenticationMethod:)` público **não tem** parâmetro `serverTrust` — nenhum challenge sintético in-process consegue exercitar o branch de pinning. **Resolução:** o mapping de disposition é extraído como helper `internal disposition(for:policy:trust:)` e unit-testado diretamente (`.matched → useCredential+credential`; `noPinForHost` fail-closed/open; failures cancel). O body do método delegate fica um thin guard → evaluate → map → completion; toda a lógica está coberta. Isto espelha o precedente `NebulaUNNotificationCenter` (delegate que não pode ser round-trip-testado headlessly) e o `BGTaskScheduler.shared` limitation do N15b.

O live `URLSession` + delegate + TLS real round-trip é uma **limitação documentada compile-only** (um harness de servidor TLS real está fora de escopo para um test target SPM Foundation-only). A wiring do delegate é compile-verified + a `NebulaUNNotificationCenter` precedent.

## Reuso de símbolos (não reinventado)

- `Data.nebulaDigest(of: .sha256)` — `Data+Nebula.swift:177` — para o SHA-256 da public-key DER. **Nenhum `import CryptoKit` novo** — o único arquivo que importa CryptoKit continua sendo `NebulaHashAlgorithm.swift` (verificado por grep `^import CryptoKit`). A invariante "só um arquivo importa CryptoKit" é preservada.
- `Data.nebulaHexEncodedString(uppercase:)` (`:47`) — para `Pin.hexDigest`.
- `Data(nebulaHexEncoded:)` failable (`:66`) — para `Pin.init?(hexDigest:)` (single source of truth do codec hex; resolve a Q "preciso de um hex parser privado?" — não).
- `NebulaHashAlgorithm.sha256` (`NebulaHashAlgorithm.swift:43`).
- `NebulaFailure: Error, Sendable` + `NebulaError.Box` — reused, não redeclarado.

## Composição com o gateway (sem mudança)

```swift
let pin = NebulaSSLPinningPin(hexDigest: "d6d4c…")!          // SHA-256 da public-key DER do cert
let policy = NebulaSSLPinning.pins(for: "api.example.com", [pin])
    .withIncludeSubdomains(true)
let pinned = NebulaHTTPSession.pinned(by: policy)           // returns (session, delegate)
let gateway = NebulaHTTPGateway(
    .init(endpoint: URL(string: "https://api.example.com")!),
    session: pinned.session
)
```

O gateway já aceita `session: URLSession` opaco; pinning pluga no layer de transporte onde pertence. Um gateway backed por `URLSession.shared` é **não** pinned — pinning é per-session via o delegate injetado.

## Postura de segurança

Pinning é **additive ao system trust**: `validateChainFirst` default `true` → o OS trust store é avaliado primeiro e pinning só adiciona uma constraint por cima — **nunca substitui** os OS anchors. Carregue um **backup pin** (guidance OWASP) para que uma rotação de cert não lock out o app. `SecTrustEvaluateWithError` pode fazer uma network fetch (OCSP / intermediate) dentro do delegate queue do URLSession; para pinning offline-only set `validateChainFirst: false` para depender só do pin matching.

## Verificação

- `rm -rf .build && swift build && swift test` → green, zero concurrency warnings. 836 tests / 171 suites.
- `swift build -c release` clean.
- `xcodebuild build` para as 5 platforms (iOS/macOS/tvOS/watchOS/visionOS) → `** BUILD SUCCEEDED **` em todas (sem gate `@available` → os tipos compilam em todas as 5).
- `xcodebuild docbuild` → `BUILD DOCUMENTATION SUCCEEDED`, zero warnings novos.
- Grep checks: nenhum `@unchecked Sendable` real em N17a; exatamente um `import CryptoKit` statement em `Sources/`; diff do `NebulaHTTPGateway.swift`/`NebulaHTTPInterceptor.swift` vazio; nenhum gate `@available` nos arquivos novos; `Package.swift` inalterado (`dependencies: []` pristine, sem `resources:`).

## Deferred (N17b / N17c)

- **N17b — streaming:** `NebulaSSEEventStream` (parser sobre `URLSession.bytes(for:).lines` — `AsyncBytes`/`AsyncLineSequence` Sendable, abaixo do floor) + `NebulaWebSocketClient` port + `NebulaURLSessionWebSocket` `final class` façade (`URLSessionWebSocketTask` non-Sendable → o mesmo pattern `NSObject`+derived-`Sendable` deste delegate se aplica ao `URLSessionWebSocketDelegate` `@objc` `@optional`). Placeholders de vault `[[nebula-websocket]]`/`[[nebula-sse]]`.
- **N17c — bodies & downloads:** `NebulaMultipartBuilder` (pure `Data` + streaming-via-temp-file via `URLSession.upload(for:fromFile:)`) + `NebulaDownload` façade (`URLSession.download(for:delegate:)` + move-to-destination `@Sendable` closure + resume data + progress `AsyncStream<Double>`) + `NebulaPagedSequence<Page>` generic pagination. Placeholder `[[nebula-download]]`.
- N18 (StoreKit IAP), A1–A3 (Aurora migration), N11b (runnable composition example), N15c (`BGContinuedProcessingTask`) per o hub [[nebula-app-readiness-research]].
- Tag `0.14.0` pendente o owner gate (consistente com 0.6.0–0.13.0; trabalho in place, não committed).

## Related

- [[nebula-network-hardening]] — research pai (N17a/b/c + interceptors).
- [[nebula-app-readiness-research]] — o hub de waves.
- [[nebula-clean-architecture-toolkit]] — os seams que esta wave estende (port/façade/config split).
- [[nebula-error-taxonomy-toolkit]] — o open-struct error pattern que `NebulaSSLPinningError` espelha.
- [[nebula-async-flow]] — o fluxo async/Sendable que o delegate consome.
- [[nebula-notifications]] — o precedente `final class : NSObject, @objc delegate, Sendable` derived (sem `@unchecked`) que este delegate replica.
- [[nebula-background-tasks]] — o contraste: onde `@unchecked` FOI necessário (non-Sendable `BGTask` system-delivered) vs aqui onde não foi.
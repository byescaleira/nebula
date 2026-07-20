---
tags: [nebula, architecture, security, keychain, auth, swift]
aliases: [nebula keychain, NebulaKeychain, NebulaSecureStore, NebulaAuthInterceptor, NebulaTokenProvider, NebulaHTTPInterceptor, nebula auth]
related: [[nebula-app-readiness-research]], [[nebula-preferences]], [[nebula-network-endpoint-client]], [[nebula-network-hardening]]
status: researched
researched: "2026-07-19"
---

# Nebula — Keychain + Auth/Session + 401 refresh-and-retry

> Research depth for the Keychain/auth dimension of [[nebula-app-readiness-research]]. Apple API claims verified against the Xcode 27 Beta 3 SDK C headers (`Security.framework/Headers/*.h`, `LocalAuthentication.framework/Headers/*.h`) + the 28-line LA `.swiftinterface`. UNVERIFIED items flagged inline.
>
> **Shipped:** the Keychain half shipped as **N9 / 0.6.0** → [[nebula-keychain]]. The 401-refresh-and-retry interceptor half shipped as **N10 / 0.7.0** → [[nebula-auth-interceptor]] (first Nebula `actor`, single-flight refresh).

## Apple-native APIs + best-practice pattern

**Keychain (Security framework — C API, no `.swiftinterface`):**
- `SecItemCopyMatching`/`SecItemAdd`/`SecItemUpdate`/`SecItemDelete` — `SecItem.h:1178/1227/1246/1277`. C functions, `CFDictionaryRef`/`CFTypeRef`. `API_AVAILABLE` com **nenhum `API_UNAVAILABLE` para tvOS/watchOS/visionOS** → Keychain está nas 5 plataformas Nebula.
- `kSecAttrAccessibleWhenUnlocked`/`AfterFirstUnlock`/`WhenPasscodeSetThisDeviceOnly`/`*ThisDeviceOnly` — `SecItem.h:605-617`. `kSecAttrAccessibleAlways` deprecated (ios 4→12).
- `SecAccessControlCreateWithFlags` — `SecAccessControl.h:124`. Flags: `kSecAccessControlBiometryAny`/`BiometryCurrentSet` (iOS 11.3), `DevicePasscode` (iOS 9), `Companion` (iOS 18 — abaixo do floor .v26, sem gate).
- `kSecAttrAccessGroup` (keychain sharing) — set em `SecItemAdd`; access groups = entitlement `Keychain-Access-Groups` + app-ID + App-Groups. **App-level (entitlement/provisioning), não Nebula.**
- `kSecUseAuthenticationContext` (bind `LAContext` a uma query para biometry-gated reads) — iOS 11+.

**Best practices (Apple DTS "Quinn the Eskimo" + WWDC19/22 + Apple Platform Security):**
- Dicionários **frescos por chamada** (state leaks entre SecItem calls → bugs de unicidade).
- Unicidade `kSecClassGenericPassword` = `kSecAttrService` + `kSecAttrAccount` apenas.
- **Prefira `SecItemUpdate` sobre delete-and-re-add** (preserva persistent refs).
- Set `kSecAttrAccessible`/`kSecAttrAccessControl` no add e **nunca update** (add-only attributes).
- **Handle `errSecInteractionNotAllowed` non-destructivamente** — device locked, não item missing; nunca delete-on-this-error (destruiria credenciais em background).
- `SecItemCopyMatching` **off the main thread** (bloqueia).
- **Nunca store auth tokens em `UserDefaults`** (WWDC19 "Cryptography and Your Apps" session 709; OWASP MASVS MSTG-STORAGE-1). Keychain com a classe mais restritiva que atende o background-access (`WhenPasscodeSetThisDeviceOnly` para sensível não-sync; `AfterFirstUnlock` para background-refresh).
- Wipe Keychain no first-launch-after-install (Keychain sobrevive a uninstall).

**LocalAuthentication (verified `LAContext.h` + 28-line LA swiftinterface):**
- `LAContext` — Obj-C class, `API_AVAILABLE(macos(10.10), ios(8.0), watchos(3.0)) API_UNAVAILABLE(tvos)` (`LAContext.h:114`). **visionOS class-level UNVERIFIED** (props individuais listam `visionos(1.0)`/`visionos(2.0)` mas a linha `API_AVAILABLE` da classe omite).
- `LAContext` **NÃO é Sendable** — a swiftinterface só adiciona `Observable, ObservableObject` (iOS 18/macOS 15/watchOS 11/visionOS 2, `API_UNAVAILABLE(tvOS)`). `ObservableObject` é inerentemente non-Sendable.
- `evaluatePolicy(_:localizedReason:reply:)` — reply `@escaping @Sendable (Bool, Error?) -> Void`; async variant iOS 15/macOS 12.
- `LAPolicy.deviceOwnerAuthenticationWithBiometrics` — `API_UNAVAILABLE(watchos, tvos)`. `deviceOwnerAuthentication` — watchOS 3+, `API_UNAVAILABLE(tvOS)`.
- `LARight`/`LARightStore` — iOS 16/macOS 13, `API_UNAVAILABLE(watchos, tvos)`, **visionOS UNVERIFIED**, `LARight` Sendability UNVERIFIED (assume non-Sendable). WWDC22 "Streamline local authorization flows" (session 10108).
- Apple guidance: **fresh `LAContext` por auth flow** (reutilizar pula biometria na próxima eval).

**Auth/session + 401 refresh-and-retry (sem framework Apple único; pattern de consenso):**
- Tokens em Keychain; session state como value type; refresh-token rotation com reuse detection.
- **Serialização de 401s concorrentes**: um `actor` owns `Task<Token, Error>`; o primeiro 401 faz refresh, 401s concorrentes `await` o mesmo in-flight `Task` (previne N refreshes paralelos).
- **Interceptor shape**: `adapt(_:)` injeta `Authorization: Bearer <token>` pre-request; `retry(_:for:with:)` detecta 401, refresha, retorna `true` para retry **uma vez** (`allowRetry: false` previne loops infinitos).
- **`NebulaRetry.withPolicy` NÃO serve para isso** — `NebulaRetry.swift:170-172`: re-roda a MESMA operação; o predicado `isRetriable` (`@Sendable (any Error) -> Bool`) decide retry mas **não muta o request**. 401-refresh-and-retry precisa de um **novo interceptor/middleware** sobre `NebulaHTTPClient`.

**WWDC verificado:** WWDC19 session 709 "Cryptography and Your Apps"; WWDC22 session 10108 "Streamline local authorization flows"; WWDC22 session 10092 "Meet passkeys". **NÃO existe** WWDC "Demystify the Secure Enclave" (isso é Black Hat 2016, não Apple).

## Sendability & availability

| API | Sendable? | Floor (iOS/macOS/tvOS/watchOS/visionOS) | Gate? |
|---|---|---|---|
| `SecItem*` (CopyMatching/Add/Update/Delete) | N/A — C | iOS 2/4/7/8 · macOS 10.6+ · **5 plataformas** | Não (abaixo floor) |
| `kSecAttrAccessible*` / `SecAccessControlCreateWithFlags` | N/A — C | iOS 4/8/11.3 · macOS 10.10+ · 5 plataformas | Não |
| `LAContext` | **NÃO** (`ObservableObject`) | iOS 8 · macOS 10.10 · watchOS 3 · **tvOS UNAVAILABLE** · **visionOS UNVERIFIED** | **Sim — `@available(tvOS, unavailable)` obrigatório** |
| `LAPolicy.deviceOwnerAuthenticationWithBiometrics` | enum (Sendable) | iOS 8 · macOS 10.12.2 · **watchOS/tvOS UNAVAILABLE** | Sim |
| `LARight`/`LARightStore` | UNVERIFIED (assume non-Sendable) | iOS 16 · macOS 13 · **watchOS/tvOS UNAVAILABLE** · **visionOS UNVERIFIED** | Sim |
| `LAError` | enum (Sendable) | iOS 8.3 · macOS 10.11 · watchOS 3 · tvOS UNAVAILABLE | Sim |
| `URLSession` (camada 401 retry) | Sendable | 5 plataformas no floor | Não |

## Nebula-scope verdict

| Surface | Veredito | Rationale | Tensão binding |
|---|---|---|---|
| `NebulaKeychain` — `final class` façade sobre `SecItem*` | **Façade** | Precedente `NebulaDefaults`: C API stateless/thread-safe sem Sendability Swift; `Mutex<NebulaKeychainConfig>` `final class` deriva `Sendable` sem `@unchecked` | **Precisa `import Security`** (Q aberta do hub) |
| `NebulaSecureStore` — port (get/set/delete `Data` por `String`) | **Port** | Espelha `NebulaPreferences` para secrets; Keychain conforma; encrypted-file/biometry-gated stores podem conformar | Nenhuma |
| `NebulaKeychainConfig` — value config (service, accessGroup?, accessible, accessControl-flags?) + `.with*` | **Config** | Espelha `NebulaGatewayConfiguration`; `accessGroup` é o seam para Keychain Sharing (entitlement fica app-level) | Nenhuma |
| `NebulaBiometry` — façade concreta sobre `LAContext` | **Defer** | `LAContext` `API_UNAVAILABLE(tvOS)` no nível da classe → não pode ser tipo 5-platform; visionOS UNVERIFIED | Alta — tvOS é first-class Nebula |
| `NebulaBiometry` — port (`evaluate(reason:) async throws -> Bool`) | **Port (tvOS-gated, defer)** | Permite app conformar impl LAContext-backed em iOS/macOS/watchOS e no-op em tvOS, sem Nebula referenciar `LAContext` | Média |
| `NebulaTokenProvider` — port (`currentToken() async -> Token?`, `refresh() async throws -> Token`) | **Port** | Seam natural que o auth-interceptor chama; app fornece concreto (lê `NebulaSecureStore`, chama refresh endpoint) | Nenhuma |
| `NebulaHTTPInterceptor` — port (`adapt`/`retry`) | **Port** | Item "Request middleware/interceptors" já no ROADMAP Later; a peça que `NebulaRetry` não fornece | Nenhuma |
| `NebulaAuthInterceptor` — concrete 401-refresh-and-retry | **Façade (adapter)** | Alta valor: envolve `NebulaHTTPClient`, injeta bearer via `NebulaTokenProvider`, em 401 coordena single refresh via `actor`-owned `Task`, retry once com request mutado | **Média — primeiro `actor` owned-by-Nebula** (CLAUDE.md permite: "use `actor` só quando shared mutable state span many call sites e um `Mutex` é awkward" — 401s concorrentes awaiting um refresh qualifica) |
| `NebulaHTTPClient.intercepted(by:)` — extension | **Port (default ext)** | Compõe interceptors em chain; sobre N5 | Nenhuma |
| Keychain Sharing (`kSecAttrAccessGroup` + entitlement) | **App-only** | Entitlement = provisioning/code-signing | Nenhuma |
| Token storage em `UserDefaults` | **App-only (anti-pattern)** | Apple proíbe; Nebula não fornece | Nenhuma |
| `LARight`/`LARightStore` façade | **Defer** | iOS 16/macOS 13 only, watchOS/tvOS unavailable, visionOS/Sendability UNVERIFIED | Alta |

## Recommended waves

- **N9 — Keychain + SecureStore port.** `NebulaSecureStore` (port, 3 byte-level reqs) + `NebulaKeychain` (`final class` Mutex-façade, SecItem C API, `kSecAttrAccessible`/`SecAccessControlCreateWithFlags`, `errSecInteractionNotAllowed` non-destructivo, fresh-dict-per-call) + `NebulaKeychainConfig` (`.with*`) + `NebulaKeychainError: NebulaFailure` bridging a `NebulaError.Kind` existente (**sem novo Kind** — verificar qual: `.network`/`.cocoa`/`.unknown` antes de shippar). 5 plataformas. Deps: nenhum. **Gated by Q (import Security).**
- **N10 — Auth interceptor + 401 refresh-and-retry.** `NebulaHTTPInterceptor` (port) + `NebulaTokenProvider` (port, `Token: Sendable`) + `NebulaAuthInterceptor` (concrete, `actor` single-flight refresh, `adapt` injeta bearer, `retry` detecta 401 via `NebulaHTTPStatusError(code: 401)`, `allowRetry: false`) + `NebulaHTTPClient.intercepted(by:)`. Deps: N9, N5, N1 (patterns — mas seam novo, não `withPolicy`). Documentar o `actor` em `DECISIONS.md`.
- **(Defer) N?? — Biometry port + LAContext façade.** `NebulaBiometry` port gated `@available(tvOS, unavailable)` + façade concreta sobre `LAContext` em iOS/macOS/watchOS only. Re-eval após N9/N10. Sem deps.

## UNVERIFIED (não citar como fato)
- `LAContext` class-level availability em **visionOS** (linha `API_AVAILABLE` omite visionOS; props individuais listam `visionos(1.0)`).
- `LARight`/`LARightStore` availability em **visionOS** + `LARight` Sendability.

## Sources
- WWDC19 709 "Cryptography and Your Apps" — https://developer.apple.com/videos/play/wwdc2019/709/
- WWDC22 10108 "Streamline local authorization flows" — https://developer.apple.com/videos/play/wwdc2022/10108/
- Apple Platform Security — Keychain data protection — https://support.apple.com/guide/security/keychain-data-protection-secb0694df1a/web
- Apple Forums DTS "SecItem: Pitfalls and Best Practices" — https://developer.apple.com/forums/thread/724013
- OWASP MASVS MSTG-STORAGE-1 — https://github.com/OWASP/owasp-mastg/blob/v1.5.0/Document/0x06d-Testing-Data-Storage.md
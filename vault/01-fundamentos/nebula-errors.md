---
tags: [foundation, errors]
aliases: [Nebula Error Foundation, nebula-error]
related: [[nebula-logging], [nebula-date-time-extensions], [nebula-codable-foundation], [nebula-data-url-extensions], [nebula-swift6-concurrency], [nebula-spm-architecture]]
---

# Nebula Error Foundation

This note designs the error subsystem for the Nebula foundation layer: a standard, `Sendable`, throwable error envelope plus a handler configuration contract, mirroring the sibling Cosmos `CosmosErrorConfiguration` pattern without any SwiftUI dependency. It is the foundation-layer sibling of `nebula-logging`.

## Scope

Nebula (foundation only) needs a uniform error shape that:
- Is `Error`-conforming and throwable, with deterministic `NSError` bridging.
- Is `Sendable` (derived conformance; no `@unchecked`) so it can cross actor boundaries and ride inside `@Sendable` handlers.
- Carries structured metadata (domain/code, kind, message, failure reason, recovery suggestions, context/coding path, underlying error, date) without retaining a non-`Sendable` `any Error`.
- Maps lossily from the common Apple error types (`NSError`, `DecodingError`, `URLError`, `CocoaError`) and from arbitrary `any Error`.
- Exposes a handler configuration (enabled flag, category, `@Sendable` handler) plus a passive default — exactly the [[nebula-logging]] contract shape.

## Ground truth verified against the installed SDK

All availability checked against `Foundation.swiftmodule/arm64e-apple-macos.swiftinterface` in Xcode 27 Beta.3 (SDK MacOSX27.0), with compile-typechecks against `-target arm64-apple-macos26.0`. The four load-bearing protocols are all annotated `@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)` — well below the Nebula `.v26` floor on all 5 platforms (visionOS 1+ via implicit back-deployment). `Mutex` (Synchronization) is macOS 15.0+ — also below the `.v26` floor. No `@available` gating is needed in Nebula at the `.v26` baseline.

`LocalizedError` (interface lines 7280-7301): four optional properties, all default `nil` — `errorDescription`, `failureReason`, `recoverySuggestion`, `helpAnchor`. When an `Error` conforming to `LocalizedError` is bridged to `NSError`, these map to the userInfo keys `NSLocalizedDescriptionKey`, `NSLocalizedFailureReasonErrorKey`, `NSLocalizedRecoverySuggestionErrorKey`, `NSHelpAnchorErrorKey` ([Apple: LocalizedError](https://developer.apple.com/documentation/foundation/localizederror)).

`CustomNSError` (lines 7302-7318): `static var errorDomain: String`, `var errorCode: Int`, `var errorUserInfo: [String: Any]`. Conforming lets a type fully control its `NSError` bridge; the default domain is the mangled Swift type name and default code is `0` ([Apple: CustomNSError](https://developer.apple.com/documentation/foundation/customnserror)). Apple's own framework errors (`URLError`, `CocoaError`, `POSIXError`, `MachError`) implement this via the internal `_BridgedStoredNSError` protocol (line 17179) — a public-facing `CustomNSError` conformance is the supported, non-internal way for Nebula to do the same.

`RecoverableError` (lines 17110-17118): `recoveryOptions: [String]` plus `attemptRecovery(optionIndex:resultHandler:)` (escaping `(Bool) -> Void`) and `attemptRecovery(optionIndex:) -> Bool`. This is the Swift surface of the classic Cocoa `NSErrorRecoveryAttempting` mechanism, which is wired into AppKit's error responder chain on macOS ([Apple archive: Recovering From Errors](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/ErrorHandlingCocoa/RecoverFromErrors/RecoverFromErrors.html)). The protocol itself is available cross-platform (iOS 8+), but the presentation machinery is AppKit-only; the escaping handler and AppKit-oriented presentation make it a poor fit for a multiplatform, `Sendable`-first foundation — see the decision in [Apple patterns adopted](#apple-patterns-adopted).

`DecodingError` / `EncodingError` already conform to `LocalizedError` in-SDK (lines 13490-13495 — `extension Swift::DecodingError : Foundation::LocalizedError {}`). `DecodingError` is an enum with cases `typeMismatch`, `valueNotFound`, `keyNotFound`, `dataCorrupted`, each carrying a `Context { codingPath: [CodingKey]; debugDescription: String; underlyingError: Error? }` ([Apple: DecodingError](https://developer.apple.com/documentation/swift/decodingerror)). The mapping init stringifies `codingPath` (since `CodingKey` is not `Sendable`-portable across the envelope boundary) and stores it in `NebulaError.Context`.

`URLError` (line 21526-21527) is a `struct : _BridgedStoredNSError` with a nested `Code : RawRepresentable<Int>, Hashable, Sendable`; constants verified include `cancelled` (21549), `badURL` (21552), `timedOut` (21555), `cannotConnectToHost` (21564), `notConnectedToInternet` (21579), `secureConnectionFailed` (21623) ([Apple: URLError](https://developer.apple.com/documentation/foundation/urlerror)). `CocoaError` (line 7226) is the parallel type for `NSCocoaErrorDomain` with file-read/write, xpc, validation, and formatting codes ([Apple: CocoaError](https://developer.apple.com/documentation/foundation/cocoaerror)). Both are mapped lossily into `NebulaError`.

`_ErrorCodeProtocol` (lines 7237-7243) provides the `~=` pattern-match operator on error codes, used by `init(error: any Error)` to dispatch on `URLError.Code`/`CocoaError.Code`.

**userInfo key constants**: `NSLocalizedDescriptionKey`, `NSLocalizedFailureReasonErrorKey`, `NSLocalizedRecoverySuggestionErrorKey`, `NSHelpAnchorErrorKey`, `NSUnderlyingErrorKey` are Clang-imported `String` constants declared in `Foundation/Headers/NSError.h` (lines 27/33/35/37/43) — NOT in the `.swiftinterface`. (The `.swiftinterface` lines 17247-17266 are the *deprecated lowercase `ErrorUserInfoKey` aliases* — `underlyingErrorKey`, `localizedDescriptionKey`, etc. — not the NS-prefixed `String` constants the design uses. The design's API choice is correct; the prior research's citation of those lines for the NS constants was wrong and is corrected here.)

## Typed throws (SE-0413)

[SE-0413](https://github.com/apple/swift-evolution/blob/main/proposals/0413-typed-throws.md) is **implemented in Swift 6.0** and therefore available in the Nebula toolchain (Swift 6.4 / Xcode 27 Beta.3, language mode v6 — verified: `func f() throws(E) -> Int { throw E.x }` typechecks against SDK 27). Syntax: `func f() throws(CatError) -> Cat`, with `throws(any Error)` equivalent to untyped `throws` and `throws(Never)` equivalent to non-throwing. The proposal's explicit guidance is decisive for Nebula:

> "Even with the introduction of typed throws into Swift, the existing (untyped) `throws` remains the better default error-handling mechanism for most Swift code."

It warns against typed throws merely because a function *currently* throws one type — that constrains future evolution. Nebula therefore:

- Keeps all **public** throwing APIs untyped (`throws`, i.e. `throws(any Error)`).
- Exposes `NebulaError` as an **optional concrete failure type** so consumers MAY declare `func f() throws(NebulaError)` and use `Result<T, NebulaError>` losslessly. SE-0413 updated `Result.init(catching:)` to `init(catching body: () throws(Failure) -> Success)` and `get()` to `throws(Failure) -> Success`, making conversion between `Result` and throwing code lossless — Nebula's `NebulaError.wrap(_:)` helper relies on this.

## The `any Error` Sendability problem

`any Error` is **not** `Sendable` (SE-0302). A `Sendable` struct therefore cannot retain an `any Error` field without `@unchecked` (forbidden by the binding constraints). The sibling `CosmosErrorConfiguration` solved this by holding a `message: String` + `code: Int?` instead of an `Error` value. NebulaError follows the same principle: the mapping initializers **consume** the source error at construction time and keep only `Sendable` fragments (domain string, code `Int`, localized strings, stringified coding path). The original existential is dropped. Consumers needing the original error must catch it before mapping. This is the single most important constraint on the design and is documented on every mapping init.

## Two compile-breaking defects caught by adversarial typecheck

Both were found by feeding the proposed design to `swiftc -typecheck` against `MacOSX27.0.sdk` at `-target arm64-apple-macos26.0`. The corrected design below typechecks clean.

1. **A `struct` cannot recursively contain itself.** The original proposal stored `underlying: NebulaError?` directly. This does NOT compile: `value type 'NebulaError' cannot have a stored property that recursively contains it` / `cycle beginning here: NebulaError? -> (some(_:): NebulaError)`. Fix: introduce a `final class Box: Sendable, Hashable` holding `let value: NebulaError` (a final class with a `Sendable` `let` gets a *derived* `Sendable` conformance — no `@unchecked`) and store `underlying: Box?`. Verified to compile.
2. **`NebulaErrorConfiguration` cannot be `Equatable`.** The original proposal declared it `Sendable, Equatable`, but it has a stored `handler: @Sendable (NebulaErrorEvent) -> Void` closure field — closures are not `Equatable`, so synthesized `Equatable` conformance is rejected (`stored property type '@Sendable (NebulaErrorEvent) -> Void' does not conform to protocol 'Equatable'`). The sibling `CosmosErrorConfiguration` is `Sendable`-only for exactly this reason. Fix: `NebulaErrorConfiguration: Sendable` (drop `Equatable`). `NebulaErrorEvent` keeps `Sendable, Equatable` (its fields — `String`, `NebulaError` [Hashable⇒Equatable], `Date` — are all Equatable). Verified to compile.

## Recommended design for Nebula

Module placement: `Sources/Nebula/Errors/` (single SPM target `Nebula`, `import Nebula`; mirrors the [[nebula-spm-architecture]] single-target rule). Files: `NebulaError.swift` (envelope + nested `Code`/`Kind`/`Context`/`Box`), `NebulaError+Mapping.swift` (lossy inits from `NSError`/`DecodingError`/`URLError`/`CocoaError`/`any Error`), `NebulaError+CustomNSError.swift` (bridge conformance), `NebulaErrorConfiguration.swift` (`NebulaErrorConfiguration` [Sendable only] + `NebulaErrorEvent`), `NebulaErrorConfig.swift` (process-wide `Mutex`-backed current config).

### `NebulaError` — the envelope

```swift
public struct NebulaError: Error, LocalizedError, CustomNSError, Sendable, Hashable {
    public struct Code: Sendable, Hashable {
        public var domain: String
        public var code: Int
        public init(domain: String, code: Int)
    }
    public enum Kind: String, Sendable, CaseIterable {
        case network, decoding, encoding, cocoa, file, validation, serialization, unknown
    }
    public struct Context: Sendable, Hashable {
        public var codingPath: [String]          // stringified DecodingError.Context.codingPath
        public var debugDescription: String?
        public var source: String?                 // caller site tag
        public init(codingPath: [String] = [], debugDescription: String? = nil, source: String? = nil)
    }

    /// Breaks the value-type recursion: a Swift `struct` cannot contain itself,
    /// so `underlying` must be boxed. `final class` with a `Sendable` `let` gets a
    /// derived `Sendable` conformance — no `@unchecked`. Verified against SDK 27.
    public final class Box: Sendable, Hashable {
        public let value: NebulaError
        public init(_ v: NebulaError) { self.value = v }
        public static func == (l: Box, r: Box) -> Bool { l.value == r.value }
        public func hash(into h: inout Hasher) { h.combine(value) }
    }

    public var code: Code
    public var kind: Kind
    public var message: String
    public var failureReason: String?
    public var recoverySuggestions: [String]
    public var helpAnchor: String?
    public var metadata: [String: String]
    public var context: Context?
    public var date: Date
    public var underlying: Box?                 // ONE nested envelope via Box — never `NebulaError?`

    public init(code: Code, kind: Kind, message: String,
                failureReason: String? = nil, recoverySuggestions: [String] = [],
                helpAnchor: String? = nil, metadata: [String: String] = [:],
                context: Context? = nil, date: Date = Date(),
                underlying: Box? = nil)

    // LocalizedError
    public var errorDescription: String? { message }
    public var recoverySuggestion: String? { recoverySuggestions.isEmpty ? nil : recoverySuggestions.joined(separator: " ") }

    // CustomNSError — deterministic NSError bridge.
    // NSLocalized* / NSUnderlyingErrorKey are Clang-imported String constants from NSError.h.
    public static var errorDomain: String { "Nebula.NebulaError" }
    public var errorCode: Int { code.code }
    public var errorUserInfo: [String: Any] {
        var info: [String: Any] = [NSLocalizedDescriptionKey: message]
        if let f = failureReason { info[NSLocalizedFailureReasonErrorKey] = f }
        if let r = recoverySuggestion { info[NSLocalizedRecoverySuggestionErrorKey] = r }
        if let h = helpAnchor { info[NSHelpAnchorErrorKey] = h }
        info["NebulaKind"] = kind.rawValue
        info["NebulaDomain"] = code.domain
        for (k, v) in metadata { info["Nebula.\(k)"] = v }
        if let u = underlying { info[NSUnderlyingErrorKey] = u.value as NSError }
        return info
    }
}
```

### Lossy mapping initializers

```swift
extension NebulaError {
    public init(_ nsError: NSError)                       // domain/code/userInfo → code/metadata; NSLocalized* → message/failureReason/recoverySuggestion
    public init(decodingError: DecodingError)            // kind = .decoding; Context.codingPath stringified
    public init(urlError: URLError)                      // kind = .network; URLError.Code.rawValue → code
    public init(cocoaError: CocoaError)                 // kind = .cocoa or .file
    public init(error: any Error)                        // dispatch on the existential; does NOT retain it

    public static func wrap<T>(_ body: () throws -> T) -> Result<T, NebulaError> {
        do { return .value(try body()) }
        catch let e as NebulaError { return .failure(e) }
        catch { return .failure(NebulaError(error: error)) }
    }
}
```

### `NebulaErrorConfiguration` — handler contract (mirrors `CosmosErrorConfiguration`)

```swift
public struct NebulaErrorEvent: Sendable, Equatable {
    public var category: String
    public var error: NebulaError                         // Sendable — safe to carry (unlike `any Error`)
    public var date: Date
    public init(category: String, error: NebulaError, date: Date = Date())
}

// Sendable ONLY — NOT Equatable. The @Sendable handler closure is not Equatable,
// so synthesized Equatable is rejected by the compiler. Mirrors CosmosErrorConfiguration,
// which is declared `: Sendable` (no Equatable) for the same reason.
public struct NebulaErrorConfiguration: Sendable {
    public var isEnabled: Bool
    public var category: String
    public var handler: @Sendable (NebulaErrorEvent) -> Void

    public init(isEnabled: Bool = true,
                category: String = "Nebula",
                handler: @escaping @Sendable (NebulaErrorEvent) -> Void = { _ in })

    public static let `default` = NebulaErrorConfiguration()

    public func report(_ error: NebulaError) {
        guard isEnabled else { return }
        handler(.init(category: category, error: error))
    }

    public func withEnabled(_ v: Bool) -> NebulaErrorConfiguration { var c = self; c.isEnabled = v; return c }
    public func withCategory(_ v: String) -> NebulaErrorConfiguration { var c = self; c.category = v; return c }
    public func withHandler(_ h: @escaping @Sendable (NebulaErrorEvent) -> Void) -> NebulaErrorConfiguration { var c = self; c.handler = h; return c }
}
```

### Process-wide current config (no SwiftUI Environment)

Nebula has no SwiftUI `@Environment`, so the Cosmos injection path is unavailable. The process-wide default is held in a `Mutex<NebulaErrorConfiguration>` (`import Synchronization`, Swift 6.0+ — see [[nebula-swift6-concurrency]]). `Mutex` is macOS 15.0+ (verified by typecheck), below the `.v26` floor:

```swift
import Synchronization

public enum NebulaErrorConfig {
    private static let current = Mutex<NebulaErrorConfiguration>(.default)
    public static func get() -> NebulaErrorConfiguration { current.withLock { $0 } }
    public static func set(_ c: NebulaErrorConfiguration) { current.withLock { $0 = c } }
}
```

This satisfies the binding constraint: no `NSLock`, no `DispatchQueue`, no `nonisolated(unsafe)` mutable globals. The `static let default` uses the once-token `swift_once` side-effect pattern.

### Typed-throws policy

Per SE-0413, public APIs use untyped `throws`; `NebulaError` is exposed as an opt-in concrete `Failure` for consumers (`func f() throws(NebulaError)`, `Result<T, NebulaError>`).

## Apple patterns adopted

- **LocalizedError 4-property surface** with nil defaults — `errorDescription`/`failureReason`/`recoverySuggestion`/`helpAnchor` (interface lines 7280-7301). `NebulaError.recoverySuggestion` joins `recoverySuggestions[]`.
- **CustomNSError** for deterministic NSError bridging — `errorDomain`/`errorCode`/`errorUserInfo` (lines 7302-7318). Default mangled-name domain is replaced with `"Nebula.NebulaError"`.
- **NS-prefixed userInfo String constants** (`NSLocalizedDescriptionKey`/`NSLocalizedFailureReasonErrorKey`/`NSLocalizedRecoverySuggestionErrorKey`/`NSHelpAnchorErrorKey`/`NSUnderlyingErrorKey`) populate `errorUserInfo` — these are Clang-imported from `Foundation/Headers/NSError.h` (lines 27/33/35/37/43), NOT the `.swiftinterface` lines 17247-17266 (which are the deprecated lowercase `ErrorUserInfoKey` aliases). The design uses the correct NS-prefixed `String` constants; verified to compile as `[String: Any]` keys.
- **Pattern-match concrete bridged errors** (`URLError`/`CocoaError`/`DecodingError`) via `as?` casts and the `~=` operator on `_ErrorCodeProtocol` (lines 7237-7243) inside `init(error: any Error)`.
- **`_BridgedStoredNSError` reference shape** studied for domain/code/userInfo extraction (lines 17179, 7226, 7734, 14640, 21526); Nebula uses the public `CustomNSError` surface instead of the internal protocol.
- **Typed throws (SE-0413)** — untyped `throws` default per proposal guidance; `Result.init(catching:)` used losslessly in `wrap(_:)`.
- **Sendable value types + `@Sendable` handlers** (SE-0302) — same pattern as `CosmosErrorConfiguration`/`CosmosLogConfiguration`; no `any Error` stored.
- **`final class Box`** to break struct value-type recursion for `underlying` — derived `Sendable` on a final class with a `Sendable` `let`, no `@unchecked`.
- **Once-token `static let default`** for the default singleton — never `nonisolated(unsafe)`.
- **`Mutex<T>` from `import Synchronization`** (Swift 6.0+, macOS 15.0+) for the process-wide current config — no `NSLock`, no `DispatchQueue`.
- **DocC** on every public symbol; **deprecation via `@available(*, deprecated, message:)`** mirroring the SDK's own deprecated `ErrorUserInfoKey` aliases (lines 17247-17266).
- **API availability IS versioning**: no `@available` gating at `.v26` because `LocalizedError`/`CustomNSError`/`RecoverableError`/`CocoaError`/`URLError` are all available iOS 8+/macOS 10.10+/tvOS 9+/watchOS 2+/visionOS 1+ and `Mutex` is macOS 15.0+ — all below the floor.

## Risks & open questions

- **`any Error` is not `Sendable`** → mapping inits are lossy (drop the existential, keep `Sendable` fragments). Documented on every init.
- **FIXED compile risk**: a `struct` cannot recursively contain itself — `underlying: NebulaError?` does not compile. Corrected to `underlying: Box?` via a `final class Box: Sendable, Hashable`.
- **FIXED compile risk**: `NebulaErrorConfiguration: Equatable` does not compile (the `@Sendable` handler closure is not Equatable). Corrected to `Sendable` only, mirroring `CosmosErrorConfiguration`. `NebulaErrorEvent` keeps `Equatable`.
- **`errorUserInfo: [String: Any]`** is non-`Sendable`; acceptable only because it is a computed property built lazily at the NSError cast boundary, never stored as a `Sendable` field.
- **NS userInfo constant citation corrected**: the NS-prefixed `String` constants are from `NSError.h`, not `.swiftinterface` lines 17247-17266 (which are the deprecated lowercase `ErrorUserInfoKey` aliases). API choice is correct.
- **`RecoverableError` deliberately NOT adopted** — `attemptRecovery(optionIndex:resultHandler:)` uses an escaping `(Bool) -> Void` tied to AppKit modal presentation (lines 17110-17118); not multiportable or `Sendable`. `recoverySuggestions[]` is surfaced via `LocalizedError.recoverySuggestion` instead.
- **Typed throws evolution lock-in** (SE-0413 warning) → public APIs stay untyped; `NebulaError` is an opt-in concrete failure only.
- **Nested `underlying: Box?`** gives one level of nesting; deep `NSError` underlying-error chains are flattened to one level (the first underlying is wrapped in a `Box`) — documented lossy behavior.
- **`date: Date` in auto-synthesized `==`** may surprise consumers; decide whether to exclude `date` from equality via a custom `==` (open).
- Open: should there be a typed-throws convenience `NebulaErrorConfiguration.capture(_ body: () throws(E) -> T) rethrows -> Result<T, E>`, or is `wrap(_:)` enough?
- Open: presentation (`NebulaErrorPresenter`) is out of scope for the foundation — left to app/UIKit/SwiftUI layers (mirrors Cosmos, which reports but does not present).
- Open: global `Mutex`-backed `NebulaErrorConfig` vs explicit-parameter DI ergonomics — current design supports both.
- Open: `NebulaError.Kind` is a closed `enum`; reopen as a `struct` if consumers need custom kinds without forking (deprecation path available).
- Open: expose a recursive `underlyingChain: [NebulaError]` accessor for logging/debugging now that the chain is boxed.

## Sources

- [Error protocol (Swift)](https://developer.apple.com/documentation/swift/error)
- [LocalizedError (Foundation)](https://developer.apple.com/documentation/foundation/localizederror)
- [CustomNSError (Foundation)](https://developer.apple.com/documentation/foundation/customnserror)
- [RecoverableError (Foundation)](https://developer.apple.com/documentation/foundation/recoverableerror)
- [CocoaError (Foundation)](https://developer.apple.com/documentation/foundation/cocoaerror)
- [URLError (Foundation)](https://developer.apple.com/documentation/foundation/urlerror)
- [DecodingError (Swift)](https://developer.apple.com/documentation/swift/decodingerror)
- [SE-0413 Typed throws](https://github.com/apple/swift-evolution/blob/main/proposals/0413-typed-throws.md)
- [Error Objects, Domains, and Codes (archive)](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/ErrorHandlingCocoa/ErrorObjectsDomains/ErrorObjectsDomains.html)
- [Recovering From Errors (archive)](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/ErrorHandlingCocoa/RecoverFromErrors/RecoverFromErrors.html)
- Foundation.swiftinterface (arm64e-apple-macos) — `/Applications/Xcode-27.0.0-Beta.3.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/Foundation.framework/Versions/C/Modules/Foundation.swiftmodule/arm64e-apple-macos.swiftinterface` (lines 7226, 7237-7243, 7280-7318, 7734, 13490-13495, 14640, 17110-17118, 17179, 17238-17266, 21526-21623)
- Foundation/Headers/NSError.h — `/Applications/Xcode-27.0.0-Beta.3.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/Foundation.framework/Versions/C/Headers/NSError.h` (lines 27/33/35/37/43 — NS-prefixed userInfo String constants)
- Synchronization.Mutex — verified via `swiftc -typecheck` against `MacOSX27.0.sdk` (available macOS 15.0+)
- CosmosErrorConfiguration.swift — `/Users/rafael.escaleira/Documents/projects/personal/cosmos/Sources/Cosmos/Base/Configuration/CosmosErrorConfiguration.swift`
- CosmosConfiguration.swift — `/Users/rafael.escaleira/Documents/projects/personal/cosmos/Sources/Cosmos/Base/Configuration/CosmosConfiguration.swift`
- Cosmos DECISIONS.md / CLAUDE.md — `/Users/rafael.escaleira/Documents/projects/personal/cosmos/DECISIONS.md`, `/Users/rafael.escaleira/Documents/projects/personal/cosmos/CLAUDE.md`

Source of truth = root docs (CLAUDE.md, ARCHITECTURE.md, DECISIONS.md, VERSIONING.md); this note is the synthesis. On conflict, the root doc wins.
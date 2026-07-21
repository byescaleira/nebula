# Keychain

A `Sendable` secure-storage port and a stateless `final class` façade over the Security.framework `SecItem*` C API.

## Overview

Nebula ships the seam **and** a concrete Security adapter. ``NebulaSecureStore``
is the architecture seam — a `Sendable` protocol with three byte-level
requirements (``NebulaSecureStore/data(forKey:)`` /
``NebulaSecureStore/setData(_:forKey:)`` / ``NebulaSecureStore/remove(forKey:)``),
each `throws` because secure storage has real failure modes (authentication
failure, the device being locked, a missing entitlement). `data(forKey:)` returns
`nil` for an absent key and `throws` for a genuine failure, so a caller can
distinguish "no secret" from "could not read the secret". The typed ergonomics
are a **default extension** built on those three, so every conformer gets them
for free:

- ``NebulaSecureStore/value(_:forKey:)`` / ``NebulaSecureStore/setValue(_:forKey:)``
  — a `Codable` bridge (JSON through `Data`, per-call coders decoupled from the
  gateway's `NebulaJSONEncoder`/`NebulaJSONDecoder`);
- ``NebulaSecureStore/rawValue(_:forKey:)`` / ``NebulaSecureStore/setRawValue(_:forKey:)``
  — a `RawRepresentable` bridge (`RawValue: Codable`).

``NebulaKeychain`` is the concrete façade over the Keychain `SecItem*` C API. An
app swaps the backing store — an encrypted store, a test double — by conforming
to ``NebulaSecureStore`` directly and implementing only the three byte-level
methods.

```swift
let keychain = NebulaKeychain(.init(service: "com.acme.app"))
try keychain.setValue(Data("token".utf8), forKey: "session-token")
let token: Data? = try keychain.data(forKey: "session-token")

try keychain.setValue(Credentials(user: "ada", token: "t0k3n"), forKey: "creds")
let creds: Credentials? = try keychain.value(Credentials.self, forKey: "creds")
```

``NebulaSecureStore`` is a **distinct** port from ``NebulaPreferences``: the
same three byte-level signatures, but `throws` and a separate seam. A Keychain
conformer must not be a drop-in for a preferences store — secrets and
user-tunable preferences have different threat models. An app injects a secure
store and a preferences store as separate seams.

### Why a `final class`, not a `Mutex`

``NebulaDefaults`` wraps `UserDefaults` in a `Mutex<UserDefaults>` because
`UserDefaults` is a **non-`Sendable` object** that must be region-isolated. The
Keychain `SecItem*` C API is different: there is **no Swift object to hold** —
they are thread-safe free functions (`SecItemAdd` / `SecItemCopyMatching` /
`SecItemUpdate` / `SecItemDelete`) parameterized by a fresh query dictionary per
call. So ``NebulaKeychain`` is a **stateless `final class`** holding an immutable
`let config: NebulaKeychainConfig` (a `Sendable` value type). A `final class`
with a single `let` `Sendable` property **derives `Sendable`** with no `Mutex`
and no `@unchecked` — the ``NebulaError/Box`` precedent, not the
``NebulaDefaults`` `Mutex` precedent. A single instance is safe to share across
tasks.

### Fresh query per call, update over delete-re-add

Every `SecItem*` call builds a fresh query dictionary (the Keychain best practice
— never mutate a shared dict). ``NebulaKeychain/setData(_:forKey:)`` updates an
existing item in place first (``NebulaKeychain/setData(_:forKey:)`` calls
`SecItemUpdate`), falling back to `SecItemAdd` only on `errSecItemNotFound` —
this preserves access control and avoids a re-prompt, rather than
delete-then-add. ``NebulaKeychain/remove(forKey:)`` is idempotent
(`errSecItemNotFound` is a no-op success). `errSecInteractionNotAllowed` (the
device is locked) is **non-destructive** — no path deletes on this error; the
item is not missing, the device is locked.

## Topics

### Port
- ``NebulaSecureStore``
- ``NebulaSecureStore/data(forKey:)``
- ``NebulaSecureStore/setData(_:forKey:)``
- ``NebulaSecureStore/remove(forKey:)``

### Codable bridge (default extension)
- ``NebulaSecureStore/value(_:forKey:)``
- ``NebulaSecureStore/setValue(_:forKey:)``

### RawRepresentable bridge (default extension)
- ``NebulaSecureStore/rawValue(_:forKey:)``
- ``NebulaSecureStore/setRawValue(_:forKey:)``

### Concrete façade
- ``NebulaKeychain``

### Configuration
- ``NebulaKeychainConfig``

### Accessibility
- ``NebulaKeychainAccessible``

### Layer errors
- ``NebulaKeychainError``
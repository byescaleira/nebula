//
//  NebulaKeychain.swift
//  Nebula
//
//  Wave N9 — App-readiness. The concrete Security.framework façade over the
// `SecItem*` C API, conforming to ``NebulaSecureStore``. A **stateless `final
// class`** holding an immutable `let config: NebulaKeychainConfig` — there is no
// Swift object to region-isolate (the `SecItem*` calls are thread-safe free
// functions parameterized by a fresh query dictionary per call), so `Sendable`
// is **derived** with no `Mutex` and no `@unchecked` (the ``NebulaError/Box``
// precedent, NOT the ``NebulaDefaults`` `Mutex` precedent). Fresh query dict per
// call (the Keychain best practice; never mutate a shared dict). `SecItemUpdate`
// over delete-re-add (preserves access control; no re-prompt).
// `errSecInteractionNotAllowed` is non-destructive — never delete on this error
// (the device is locked, not the item missing). See
// vault/03-padroes/nebula-keychain.md.
//

import Foundation
import Security

/// The concrete Security.framework façade over the Keychain `SecItem*` C API.
///
/// A stateless `final class` conforming to ``NebulaSecureStore``. The config is
/// immutable per-instance; build a new `NebulaKeychain` from a `.with*`-mutated
/// ``NebulaKeychainConfig`` to change partition / accessibility. The `SecItem*`
/// calls are thread-safe free functions, so a single instance is safe to share
/// across tasks — no `Mutex` is needed.
///
/// ```swift
/// let keychain = NebulaKeychain(.init(service: "com.acme.app"))
/// try keychain.setValue(Data("token".utf8), forKey: "session-token")
/// let token: Data? = try keychain.data(forKey: "session-token")
/// ```
public final class NebulaKeychain: NebulaSecureStore {

    /// The immutable Keychain configuration.
    public let config: NebulaKeychainConfig

    /// Creates a Keychain façade from a configuration.
    public init(_ config: NebulaKeychainConfig) {
        self.config = config
    }

    // MARK: - NebulaSecureStore

    /// Returns the raw `Data` stored for `key`, or `nil` when absent.
    public func data(forKey key: String) throws -> Data? {
        var query = baseQuery(account: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        case errSecInteractionNotAllowed:
            throw NebulaKeychainError.interactionNotAllowed(status: status)
        default:
            throw NebulaKeychainError.unknown(
                "Keychain read failed (OSStatus \(status))",
                status: status
            )
        }
    }

    /// Stores `value` for `key`, or removes the key when `value` is `nil`.
    public func setData(_ value: Data?, forKey key: String) throws {
        guard let value else {
            try remove(forKey: key)
            return
        }
        // Update first — preserves access control and avoids a re-prompt. On
        // not-found, fall through to add.
        let query = baseQuery(account: key)
        let attributesToUpdate: [String: Any] = [kSecValueData as String: value]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            // Add below.
            break
        case errSecInteractionNotAllowed:
            throw NebulaKeychainError.interactionNotAllowed(status: updateStatus)
        default:
            throw NebulaKeychainError.unknown(
                "Keychain update failed (OSStatus \(updateStatus))",
                status: updateStatus
            )
        }

        var addQuery = baseQuery(account: key)
        addQuery[kSecValueData as String] = value
        addQuery[kSecAttrAccessible as String] = config.accessible.cfString

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            throw NebulaKeychainError.duplicateItem(status: addStatus)
        case errSecInteractionNotAllowed:
            throw NebulaKeychainError.interactionNotAllowed(status: addStatus)
        default:
            throw NebulaKeychainError.unknown(
                "Keychain add failed (OSStatus \(addStatus))",
                status: addStatus
            )
        }
    }

    /// Removes any value stored for `key` (a no-op when absent).
    public func remove(forKey key: String) throws {
        let query = baseQuery(account: key)
        let status = SecItemDelete(query as CFDictionary)

        switch status {
        case errSecSuccess, errSecItemNotFound:
            // Idempotent: not-found is a no-op success.
            return
        case errSecInteractionNotAllowed:
            // Non-destructive — the device is locked, not the item missing. Do
            // NOT treat this as a delete.
            throw NebulaKeychainError.interactionNotAllowed(status: status)
        default:
            throw NebulaKeychainError.unknown(
                "Keychain delete failed (OSStatus \(status))",
                status: status
            )
        }
    }

    // MARK: - Query building

    /// The immutable match attributes shared by every `SecItem*` call for `account`:
    /// `kSecClassGenericPassword` + the config's `service` + `account` + optional
    /// `accessGroup` + optional `kSecUseDataProtectionKeychain`. A fresh dict per
    /// call (never mutate a shared dict).
    private func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: config.service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup = config.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        if config.useDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }
}
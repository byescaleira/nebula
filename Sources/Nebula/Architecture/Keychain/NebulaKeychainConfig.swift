//
//  NebulaKeychainConfig.swift
//  Nebula
//
//  Wave N9 — App-readiness. The Keychain configuration: a `Sendable` value
//  carrying the cross-cutting Keychain contract (service, access group,
//  accessibility class, data-protection keychain toggle). All fields are plain
//  values (no `@Sendable` closure) so the struct is `Equatable`. Fluent `.with*`
//  builders mirror ``NebulaGatewayConfiguration``/``NebulaStandards``. There is
//  no `static let default` — a `service` is required (mirrors ``NebulaDefaults``
//  taking a `UserDefaults`), and no process-wide `Mutex` accessor — the caller
//  owns the instance. See vault/03-padroes/nebula-keychain.md.
//

import Foundation

/// The Nebula Keychain configuration.
///
/// A `Sendable`, `Equatable` value describing how a ``NebulaKeychain`` talks to
/// the Security.framework `SecItem*` C API:
///
/// - ``service`` — the `kSecAttrService` value scoping every item. Required
///   (a Keychain partition with no service is meaningless);
/// - ``accessGroup`` — the optional `kSecAttrAccessGroup` (an app-level
///   entitlement). Nebula exposes the seam only — it never asserts an
///   entitlement. `nil` uses the app's default partition;
/// - ``accessible`` — the ``NebulaKeychainAccessible`` class
///   (`kSecAttrAccessible`). Defaults to ``NebulaKeychainAccessible/whenUnlocked``
///   (least-surprising for a library; credential-storing apps should pick
///   ``NebulaKeychainAccessible/afterFirstUnlockThisDeviceOnly``);
/// - ``useDataProtectionKeychain`` — sets `kSecUseDataProtectionKeychain`
///   (the modern, cross-platform, no-prompt, sandbox-friendly keychain). Defaults
///   to `true` — the right production default. On an unsigned macOS test host
///   this may return `errSecMissingEntitlement`; tests override to `false` to
///   use the login-keychain path (see `ArchitectureKeychainTests`).
///
/// The config is immutable per-instance; `.with*` returns a mutated copy the
/// caller builds a new ``NebulaKeychain`` from. There is **no** process-wide
/// `Mutex<NebulaKeychainConfig>` accessor (mirrors ``NebulaDefaults`` — the
/// caller owns the instance; a Keychain partition is per-store, not global).
public struct NebulaKeychainConfig: Sendable, Equatable {

    /// The `kSecAttrService` value scoping every Keychain item.
    public let service: String
    /// The optional `kSecAttrAccessGroup` (an app-level entitlement). Nebula
    /// exposes the seam only — it never asserts an entitlement. `nil` uses the
    /// app's default partition.
    public let accessGroup: String?
    /// The accessibility class (`kSecAttrAccessible`) for added items.
    public let accessible: NebulaKeychainAccessible
    /// Sets `kSecUseDataProtectionKeychain` — the modern, cross-platform,
    /// no-prompt, sandbox-friendly keychain. Defaults to `true`.
    public let useDataProtectionKeychain: Bool

    /// Creates a configuration.
    ///
    /// - Parameters:
    ///   - service: the `kSecAttrService` value scoping every item (required);
    ///   - accessGroup: the optional `kSecAttrAccessGroup` (app-level entitlement);
    ///   - accessible: the accessibility class (defaults to
    ///     ``NebulaKeychainAccessible/whenUnlocked``);
    ///   - useDataProtectionKeychain: sets `kSecUseDataProtectionKeychain`
    ///     (defaults to `true`).
    public init(
        service: String,
        accessGroup: String? = nil,
        accessible: NebulaKeychainAccessible = .whenUnlocked,
        useDataProtectionKeychain: Bool = true
    ) {
        self.service = service
        self.accessGroup = accessGroup
        self.accessible = accessible
        self.useDataProtectionKeychain = useDataProtectionKeychain
    }

    // MARK: - Fluent builders

    /// Returns a copy with the service replaced.
    public func withService(_ service: String) -> NebulaKeychainConfig {
        .init(service: service, accessGroup: accessGroup, accessible: accessible, useDataProtectionKeychain: useDataProtectionKeychain)
    }

    /// Returns a copy with the access group replaced.
    public func withAccessGroup(_ accessGroup: String?) -> NebulaKeychainConfig {
        .init(service: service, accessGroup: accessGroup, accessible: accessible, useDataProtectionKeychain: useDataProtectionKeychain)
    }

    /// Returns a copy with the accessibility class replaced.
    public func withAccessible(_ accessible: NebulaKeychainAccessible) -> NebulaKeychainConfig {
        .init(service: service, accessGroup: accessGroup, accessible: accessible, useDataProtectionKeychain: useDataProtectionKeychain)
    }

    /// Returns a copy with the data-protection-keychain toggle replaced.
    public func withUseDataProtectionKeychain(_ useDataProtectionKeychain: Bool) -> NebulaKeychainConfig {
        .init(service: service, accessGroup: accessGroup, accessible: accessible, useDataProtectionKeychain: useDataProtectionKeychain)
    }
}
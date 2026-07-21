//
//  NebulaKeychainAccessible.swift
//  Nebula
//
//  Wave N9 — App-readiness. The Keychain item accessibility class: a `Sendable`
//  enum mapping 1:1 to the `kSecAttrAccessible*` `CFString` constants from
//  `Security.framework`. All five cases are available on every Nebula platform
//  (iOS/macOS/tvOS/watchOS/visionOS) — no `@available` gates. See
//  vault/03-padroes/nebula-keychain.md.
//

import Foundation
import Security

/// The accessibility class of a Keychain item — when it may be read.
///
/// Maps 1:1 to the `kSecAttrAccessible*` `CFString` constants. Pick the most
/// restrictive class that still meets the use case (Apple's guidance). The
/// `*ThisDeviceOnly` variants never sync to other devices via iCloud Keychain —
/// appropriate for device-bound secrets.
///
/// - Note: This is the simple `kSecAttrAccessible` path. Biometry-gated items
///   (`SecAccessControlCreateWithFlags`) are deferred — `LAContext` is
///   `API_UNAVAILABLE(tvOS)` at the class level, so a biometry surface cannot
///   be 5-platform.
public enum NebulaKeychainAccessible: Sendable, Equatable, Hashable {

    /// The item is accessible only while the device is unlocked (`kSecAttrAccessibleWhenUnlocked`).
    case whenUnlocked

    /// The item is accessible after the first unlock until the device is rebooted
    /// (`kSecAttrAccessibleAfterFirstUnlock`).
    case afterFirstUnlock

    /// The item is accessible only while the device is unlocked, and only when a
    /// passcode is set; never syncs (`kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`).
    case whenPasscodeSetThisDeviceOnly

    /// Like ``whenUnlocked`` but never syncs to other devices
    /// (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`).
    case whenUnlockedThisDeviceOnly

    /// Like ``afterFirstUnlock`` but never syncs to other devices
    /// (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
    case afterFirstUnlockThisDeviceOnly

    /// The `kSecAttrAccessible` constant to set on a Keychain add query.
    var cfString: CFString {
        switch self {
        case .whenUnlocked:                      return kSecAttrAccessibleWhenUnlocked
        case .afterFirstUnlock:                  return kSecAttrAccessibleAfterFirstUnlock
        case .whenPasscodeSetThisDeviceOnly:     return kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        case .whenUnlockedThisDeviceOnly:        return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        case .afterFirstUnlockThisDeviceOnly:    return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
    }
}